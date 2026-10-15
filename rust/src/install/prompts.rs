// JSON sent to Swift for 2FA and certificate prompts, and parsing the replies.

use super::*;

pub(super) fn two_factor_json(p: &TwoFactorCallbackParams) -> String {
    serde_json::json!({
        "unknown": p.unknown,
        "sms": p.sms,
        "lastError": p.last_error,
        "selectedNumberId": p.selected_number_id,
        "numbers": p.numbers.iter().map(|n| serde_json::json!({
            "id": n.id,
            "number": n.number_with_dial_code,
        })).collect::<Vec<_>>(),
    })
    .to_string()
}

pub(super) fn parse_two_factor(reply: &str) -> TwoFactorCallbackResponse {
    let reply = reply.trim();
    if let Some(code) = reply.strip_prefix("code:") {
        return TwoFactorCallbackResponse::SubmitCode(code.trim().to_string());
    }
    if let Some(id) = reply.strip_prefix("sms:").and_then(|s| s.trim().parse::<u32>().ok()) {
        return TwoFactorCallbackResponse::SendSms(id);
    }
    match reply {
        "devices" => TwoFactorCallbackResponse::SendToDevices,
        "resend" => TwoFactorCallbackResponse::ResendCode,
        _ => TwoFactorCallbackResponse::Abort,
    }
}

pub(super) fn certs_json(certs: &[DevelopmentCertificate]) -> String {
    serde_json::Value::Array(
        certs
            .iter()
            .map(|c| {
                serde_json::json!({
                    "serial": c.serial_number.clone().unwrap_or_default(),
                    "name": c.name.clone().unwrap_or_default(),
                    "machine": c.machine_name.clone().unwrap_or_default(),
                })
            })
            .collect(),
    )
    .to_string()
}
