// What to do with an app's extensions (PlugIns) when signing, the three choices
// SideStore offers: keep them with their own App IDs, keep them but sign them with
// the main app's profile, or strip them out.

use super::*;
use isideload::dev::app_groups::AppGroupsApi;
use isideload::sideload::application::Application;
use isideload::util::callbacks::MaxCertsCallback;

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum ExtensionsMode {
    /// Every extension gets its own App ID and profile. A free Apple ID only has
    /// 10 App IDs a week, so apps with many extensions use them up quickly.
    Keep,
    /// Extensions stay in the app but are signed with the main app's profile and
    /// entitlements, so only one App ID is used. Some extensions won't run this way.
    MainProfile,
    /// PlugIns and Extensions are deleted before signing.
    Remove,
}

impl ExtensionsMode {
    pub(super) fn from_raw(raw: i32) -> Self {
        match raw {
            1 => Self::MainProfile,
            2 => Self::Remove,
            _ => Self::Keep,
        }
    }
}

/// Deletes the app's extensions. Frameworks stay: the app needs them to launch.
pub(super) fn remove_extensions(app: &Path) -> Result<(), String> {
    for folder in ["PlugIns", "Extensions"] {
        let dir = app.join(folder);
        if dir.exists() {
            std::fs::remove_dir_all(&dir).map_err(|e| err(&format!("Couldn't remove {folder}"), e))?;
        }
    }
    Ok(())
}

/// isideload's `sign_app`, except only the main app gets an App ID and every
/// extension is signed with the main app's profile and entitlements.
#[allow(clippy::too_many_arguments)]
pub(super) async fn sign_with_main_profile<C: MaxCertsCallback>(
    dev: &mut DeveloperSession,
    team: &DeveloperTeam,
    apple_id: &str,
    machine_name: &str,
    storage: &dyn SideloadingStorage,
    max_certs: &MaxCertsBehavior<C>,
    app_dir: PathBuf,
    udid: &str,
    cbs: Callbacks,
) -> Result<PathBuf, String> {
    let cert = CertificateIdentity::retrieve(machine_name, apple_id, dev, team, storage, max_certs)
        .await
        .map_err(|e| err("Couldn't get a signing certificate", e))?;
    cbs.progress("Signing…", 0.1);

    let mut app = Application::new(app_dir).map_err(|e| err("Couldn't read the app", e))?;
    let special = app.get_special_app();
    let main_bundle_id = app.main_bundle_id().map_err(|e| err("Couldn't read the bundle ID", e))?;
    let main_name = app.main_app_name().map_err(|e| err("Couldn't read the app name", e))?;
    let main_identifier = format!("{main_bundle_id}.{}", team.team_id);
    app.update_bundle_id(&main_bundle_id, &main_identifier)
        .map_err(|e| err("Couldn't update the bundle IDs", e))?;

    // Only the main App ID: that's the point of this mode.
    let existing = dev
        .list_app_ids(team, None::<DeveloperDeviceType>)
        .await
        .map_err(|e| err("Couldn't list App IDs", e))?;
    let mut app_id = match existing.app_ids.into_iter().find(|a| a.identifier == main_identifier) {
        Some(id) => id,
        None => dev
            .add_app_id(team, &main_name, &main_identifier, None::<DeveloperDeviceType>)
            .await
            .map_err(|e| err("Couldn't register the App ID", e))?,
    };

    let group_identifier = format!(
        "group.{}",
        if special == Some(SpecialApp::SideStoreLc) {
            format!("com.SideStore.SideStore.{}", team.team_id)
        } else {
            main_identifier.clone()
        }
    );
    let group = dev
        .ensure_app_group(team, &main_name, &group_identifier, None::<DeveloperDeviceType>)
        .await
        .map_err(|e| err("Couldn't register the app group", e))?;
    app_id
        .ensure_group_feature(dev, team)
        .await
        .map_err(|e| err("Couldn't enable app groups", e))?;
    dev.assign_app_group(team, &group, &app_id, None::<DeveloperDeviceType>)
        .await
        .map_err(|e| err("Couldn't assign the app group", e))?;
    cbs.progress("Signing…", 0.15);

    app.apply_special_app_behavior(&special, &group_identifier, &cert, None, Some(udid))
        .await
        .map_err(|e| err("Couldn't prepare the app", e))?;

    let profile = dev
        .download_team_provisioning_profile(team, &app_id, None::<DeveloperDeviceType>)
        .await
        .map_err(|e| err("Couldn't download the provisioning profile", e))?;
    let entitlements = profile_entitlements(profile.encoded_profile.as_ref());

    // Every extension borrows the main profile and its entitlements.
    let mut borrowed: Vec<(String, isideload::dev::app_ids::Profile, plist::Dictionary)> = app
        .bundle
        .app_extensions()
        .iter()
        .filter_map(|ext| ext.bundle_identifier().map(str::to_string))
        .map(|id| (id, profile.clone(), entitlements.clone()))
        .collect();

    app.bundle.write_info().map_err(|e| err("Couldn't write Info.plist", e))?;
    for ext in app.bundle.app_extensions_mut() {
        ext.write_info().map_err(|e| err("Couldn't write an extension's Info.plist", e))?;
    }
    for framework in app.bundle.frameworks_mut() {
        framework.write_info().map_err(|e| err("Couldn't write a framework's Info.plist", e))?;
    }
    cbs.progress("Signing…", 0.3);

    let sign_progress = move |f: f32| {
        cbs.progress("Signing…", f64::from(f).clamp(0.0, 1.0));
        std::future::ready(())
    };
    isideload::sideload::sign::sign(&mut app, &cert, &profile, &mut borrowed, &special, team, Some(sign_progress))
        .await
        .map_err(|e| err("Signing failed", e))?;

    Ok(app.bundle.bundle_dir.clone())
}

/// The Entitlements dictionary inside a CMS-wrapped provisioning profile.
fn profile_entitlements(bytes: &[u8]) -> plist::Dictionary {
    let find = |needle: &[u8]| bytes.windows(needle.len()).position(|w| w == needle);
    let (Some(start), Some(end)) = (find(b"<?xml"), find(b"</plist>")) else {
        return plist::Dictionary::new();
    };
    plist::from_bytes::<plist::Dictionary>(&bytes[start..end + b"</plist>".len()])
        .ok()
        .and_then(|d| d.get("Entitlements").and_then(|v| v.as_dictionary()).cloned())
        .unwrap_or_default()
}
