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
typedef void (*AltLoadAppleTvPinCb)(void *ctx);

typedef struct AltLoadAppleTvSession AltLoadAppleTvSession;

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

AltLoadAppleTvSession *altload_apple_tv_session_new(void);

int32_t altload_apple_tv_session_run(AltLoadAppleTvSession *session,
                                      const char *host,
                                      uint16_t port,
                                      const char *name,
                                      const char *out_path,
                                      AltLoadAppleTvPinCb pin_cb,
                                      void *ctx,
                                      AltLoadResult *out);

int32_t altload_apple_tv_session_submit_pin(AltLoadAppleTvSession *session,
                                             const char *pin);

void altload_apple_tv_session_cancel(AltLoadAppleTvSession *session);
void altload_apple_tv_session_free(AltLoadAppleTvSession *session);

void altload_result_free(AltLoadResult *r);


/* ---- On-device sideloading (rust/src/install.rs) ---- */

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
} AltLoadInstallConfig;

typedef struct {
    char *error;
    char *bundle_id;
    char *app_name;
    char *app_version;
    char *udid;
    char *team_id;
    int64_t expiration_unix;
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

#ifdef __cplusplus
}
#endif

#endif // ALTLOAD_H
