// Pairing host forked from idevice's ffi/src/pairable_host.rs with the mDNS advertising moved
// to the Swift side (NetService) to avoid the iOS multicast entitlement.
#ifndef ALTLOAD_H
#define ALTLOAD_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*AltLoadReadyCb)(void *ctx,
                                const char *service_id,
                                uint16_t port,
                                const char *const *txt_keys,
                                const char *const *txt_vals,
                                size_t txt_count);

typedef void (*AltLoadPinCb)(const char *pin, void *ctx);

typedef struct {
    char *error;
    char *device_name;
    char *device_model;
    char *device_udid;
    char *pairing_file_path;
    char *host_alt_irk_hex;
} AltLoadResult;

int32_t altload_run_host(const char *bind_addr,
                          uint16_t port,
                          const char *name,
                          const char *model,
                          const char *out_path,
                          AltLoadReadyCb ready_cb,
                          AltLoadPinCb pin_cb,
                          void *ctx,
                          AltLoadResult *out);

void altload_result_free(AltLoadResult *r);


/* ---- On-device sideloading (core/src/install/mod.rs) ---- */

typedef void (*AltLoadProgressCb)(void *ctx, const char *stage, double fraction); /* fraction < 0: indeterminate */
typedef void (*AltLoadPromptCb)(void *ctx, int32_t kind, const char *json);       /* 1 = two-factor, 2 = revoke certificates */

typedef struct {
    const char *host;
    uint16_t port;
    const char *identifier; /* TXT "identifier" of _remotepairing._tcp */
    const char *auth_tag;   /* TXT "authTag" */
} AltLoadEndpoint;

typedef struct {
    const char *apple_id;
    const char *password;
    const char *anisette_url;
    const char *pairing_file_path;
    const char *host_name;
    const AltLoadEndpoint *endpoints;
    size_t endpoint_count;
    const char *ipa_path;
    const char *device_name;
    const char *machine_name;
    const char *server_id;
    /* Comma-separated App Store Connect capability IDs to enable on the app's
       App ID before signing (e.g. "INCREASED_MEMORY_LIMIT,PUSH_NOTIFICATIONS").
       NULL or "" for none. */
    const char *capabilities;
    /* App extensions: 0 keep, 1 keep and sign with the main profile, 2 remove. */
    int32_t extensions_mode;
} AltLoadInstallConfig;

typedef struct {
    char *error;
    char *bundle_id;
    char *app_name;
    char *app_version;
    char *udid;
    char *team_id;
    int64_t expiration_unix;
    char *certificates; /* the profile's developer certificates: DER in hex, comma-separated */
} AltLoadInstallResult;

typedef struct AltLoadInstallSession AltLoadInstallSession;

AltLoadInstallSession *altload_install_session_new(void);
int32_t altload_install_session_run(AltLoadInstallSession *session,
                                    const AltLoadInstallConfig *config,
                                    AltLoadProgressCb progress_cb,
                                    AltLoadPromptCb prompt_cb,
                                    void *ctx,
                                    AltLoadInstallResult *out);
int32_t altload_install_session_respond(AltLoadInstallSession *session, const char *response);
void altload_install_session_cancel(AltLoadInstallSession *session);
void altload_install_session_free(AltLoadInstallSession *session);
void altload_install_result_free(AltLoadInstallResult *r);


/* ---- Certificate manager: your own Apple ID (core/src/install/mod.rs) ---- */

/* Runs {"op":"overview"} or {"op":"revoke","serials":[...]} against the Apple
   ID's own team. Reuses an AltLoadInstallSession for 2FA prompts and cancel.
   Returns 0 with overview JSON in *out_json, or 1 with an error message.
   Free *out_json with altload_string_free. Blocking. */
int32_t altload_account_session_run(AltLoadInstallSession *session,
                                    const char *apple_id,
                                    const char *password,
                                    const char *anisette_url,
                                    const char *request_json,
                                    AltLoadProgressCb progress_cb,
                                    AltLoadPromptCb prompt_cb,
                                    void *ctx,
                                    char **out_json);
void altload_string_free(char *s);


/* ---- Device ops: on-device AltServer + files into apps (core/src/install/device.rs) ---- */

/* Opens the tunnel from config (pairing_file_path, host_name, endpoints; the
   Apple ID fields are ignored) and runs one op from request_json:
   install_app, install_profiles, remove_profiles, remove_app, list_apps, place_file.
   Returns 0 with result JSON in *out_json, or 1 with an error message.
   Free *out_json with altload_string_free. Blocking. */
int32_t altload_device_run(const AltLoadInstallConfig *config,
                           const char *request_json,
                           AltLoadProgressCb progress_cb,
                           void *ctx,
                           char **out_json);

/* ---- JIT sessions (core/src/install/jit.rs) ---- */

/* A launched (or running) app held by debugserver, driven one packet at a time.
   Every call but altload_debug_stop blocks; use one thread per session. */
typedef struct AltLoadDebugSession AltLoadDebugSession;

/* request_json: {"ddiDir":"/…/DDI","bundleId":"com.x"} to launch the app
   suspended, or {"ddiDir":…,"pid":n} for a running process. Returns 0 with the
   session and {"pid":n} in *out_json, or 1 with an error in *out_json. */
int32_t altload_debug_open(const AltLoadInstallConfig *config,
                           const char *request_json,
                           AltLoadProgressCb progress_cb,
                           void *ctx,
                           AltLoadDebugSession **out_session,
                           char **out_json);
uint64_t altload_debug_pid(const AltLoadDebugSession *session);
/* One GDB remote packet ("vAttach;1a2b", "c", "m1000,4", "D", …); 0 with the reply, 1 with an error. */
int32_t altload_debug_send(const AltLoadDebugSession *session, const char *command, char **out_reply);
/* Resumes with `resume` (NULL or "" for "c") for at most timeout_ms; 0 with the
   stop reply, or an empty reply when it timed out (the app is then paused). */
int32_t altload_debug_continue(const AltLoadDebugSession *session, const char *resume, uint64_t timeout_ms, char **out_reply);
/* Makes [address, address + length) usable for JIT; 0 with "OK", 1 with an error. */
int32_t altload_debug_prepare(const AltLoadDebugSession *session, uint64_t address, uint64_t length, char **out_reply);
/* Ends the call in progress and every later one. Safe from any thread. */
void altload_debug_stop(const AltLoadDebugSession *session);
/* Detaches if still attached, closes the tunnel and frees the session. */
void altload_debug_close(AltLoadDebugSession *session);

/* Move / end a running {"op":"simulate_location"} (which blocks until stopped). */
void altload_location_update(double latitude, double longitude);
void altload_location_stop(void);

#ifdef __cplusplus
}
#endif

#endif // ALTLOAD_H
