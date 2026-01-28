/**
 * PasskeyAuth Hook
 *
 * Handles WebAuthn/Passkey authentication using the browser's native API.
 * Also handles device detection (iOS mobile) and passkey support detection.
 * Uses builtin browser functionality (parseRequestOptionsFromJSON) when available.
 */
const PasskeyAuth = {
    mounted() {
        console.log("[PasskeyAuth] Hook mounted", {
            element: this.el,
            elementId: this.el?.id,
            elementClasses: this.el?.className,
            hookName: "PasskeyAuth"
        });

        // Device detection: Detect if device is an iPhone or iPad (iOS mobile device)
        const userAgent = navigator.userAgent;
        const isIOSMobile = /iPhone|iPad|iPod/.test(userAgent);
        
        console.log("[PasskeyAuth] Device detection", {
            userAgent: userAgent,
            isIOSMobile: isIOSMobile
        });

        if (isIOSMobile) {
            console.log("[PasskeyAuth] Detected iOS mobile device, pushing device_detected event");
            // Send event to LiveView to update the assign
            this.pushEvent("device_detected", { device: "ios_mobile" });
            console.log("[PasskeyAuth] device_detected event pushed");
        } else {
            console.log("[PasskeyAuth] Not an iOS mobile device");
        }

        // Check if WebAuthn/Passkey is supported
        const hasPublicKeyCredential = typeof window.PublicKeyCredential !== "undefined";
        const publicKeyCredentialValue = window.PublicKeyCredential;
        
        console.log("[PasskeyAuth] Passkey support check", {
            hasPublicKeyCredential: hasPublicKeyCredential,
            publicKeyCredentialType: typeof window.PublicKeyCredential,
            publicKeyCredentialValue: publicKeyCredentialValue,
            windowKeys: Object.keys(window).filter(k => k.toLowerCase().includes("credential") || k.toLowerCase().includes("webauthn") || k.toLowerCase().includes("passkey"))
        });

        const isPasskeySupported = hasPublicKeyCredential;
        
        console.log("[PasskeyAuth] Pushing passkey_support_detected event", {
            supported: isPasskeySupported,
            eventData: { supported: isPasskeySupported }
        });

        // Send event to LiveView with passkey support status
        try {
            this.pushEvent("passkey_support_detected", { supported: isPasskeySupported });
            console.log("[PasskeyAuth] passkey_support_detected event pushed successfully", {
                supported: isPasskeySupported
            });
        } catch (error) {
            console.error("[PasskeyAuth] Error pushing passkey_support_detected event", error);
        }

        // If WebAuthn is not supported, return early
        if (!isPasskeySupported) {
            console.warn("[PasskeyAuth] WebAuthn/Passkey not supported in this browser - hook will not handle authentication");
            return;
        }

        console.log("[PasskeyAuth] WebAuthn is supported, setting up authentication challenge handler");

        // Listen for authentication challenge from LiveView
        this.handleEvent("create_authentication_challenge", async ({ options }) => {
            console.log("[PasskeyAuth] create_authentication_challenge event received", {
                options: options,
                optionsKeys: options ? Object.keys(options) : null,
                hasChallenge: !!options?.challenge,
                hasAllowCredentials: !!options?.allowCredentials,
                allowCredentialsLength: options?.allowCredentials?.length || 0
            });

            try {
                // Check if browser supports JSON-based WebAuthn API
                const jsonWebAuthnSupport = !!window.PublicKeyCredential?.parseRequestOptionsFromJSON;
                
                console.log("[PasskeyAuth] Browser capabilities", {
                    jsonWebAuthnSupport: jsonWebAuthnSupport,
                    hasParseRequestOptionsFromJSON: !!window.PublicKeyCredential?.parseRequestOptionsFromJSON,
                    hasToJSON: !!window.PublicKeyCredential?.prototype?.toJSON
                });

                let credential;

                if (jsonWebAuthnSupport) {
                    console.log("[PasskeyAuth] Using modern JSON-based WebAuthn API");
                    // Use modern JSON-based API (Chrome 108+, Safari 16.4+, Firefox 119+)
                    const publicKey = PublicKeyCredential.parseRequestOptionsFromJSON({ publicKey: options });
                    console.log("[PasskeyAuth] Parsed publicKey options", {
                        challenge: publicKey.challenge ? "present" : "missing",
                        rpId: publicKey.rpId,
                        allowCredentials: publicKey.allowCredentials?.length || 0,
                        userVerification: publicKey.userVerification
                    });
                    
                    console.log("[PasskeyAuth] Calling navigator.credentials.get()...");
                    credential = await navigator.credentials.get({ publicKey });
                    console.log("[PasskeyAuth] navigator.credentials.get() completed", {
                        hasCredential: !!credential,
                        credentialId: credential?.id,
                        credentialType: credential?.type
                    });
                } else {
                    console.log("[PasskeyAuth] Using fallback traditional WebAuthn API");
                    // Fallback to traditional API (requires manual Base64 encoding/decoding)
                    // Convert base64url strings to ArrayBuffer
                    console.log("[PasskeyAuth] Converting challenge to ArrayBuffer", {
                        challengeLength: options.challenge?.length,
                        challengePreview: options.challenge?.substring(0, 20)
                    });
                    
                    const publicKey = {
                        ...options,
                        challenge: base64UrlToArrayBuffer(options.challenge)
                    };

                    console.log("[PasskeyAuth] Built publicKey object", {
                        hasChallenge: !!publicKey.challenge,
                        challengeType: publicKey.challenge?.constructor?.name,
                        rpId: publicKey.rpId,
                        userVerification: publicKey.userVerification
                    });

                    // Only include allowCredentials if it exists (non-discoverable mode)
                    // If omitted, browser will show native account picker (discoverable credentials)
                    if (options.allowCredentials && options.allowCredentials.length > 0) {
                        console.log("[PasskeyAuth] Processing allowCredentials (non-discoverable mode)", {
                            count: options.allowCredentials.length
                        });
                        publicKey.allowCredentials = options.allowCredentials.map(cred => ({
                            ...cred,
                            id: base64UrlToArrayBuffer(cred.id)
                        }));
                    } else {
                        console.log("[PasskeyAuth] No allowCredentials - using discoverable credentials mode (native account picker)");
                    }

                    console.log("[PasskeyAuth] Calling navigator.credentials.get() with fallback API...");
                    credential = await navigator.credentials.get({ publicKey });
                    console.log("[PasskeyAuth] navigator.credentials.get() completed (fallback)", {
                        hasCredential: !!credential,
                        credentialId: credential?.id,
                        credentialType: credential?.type
                    });

                    // Convert ArrayBuffers back to base64url strings
                    if (credential) {
                        console.log("[PasskeyAuth] Converting credential response to base64url", {
                            hasRawId: !!credential.rawId,
                            hasResponse: !!credential.response,
                            hasAuthenticatorData: !!credential.response?.authenticatorData,
                            hasClientDataJSON: !!credential.response?.clientDataJSON,
                            hasSignature: !!credential.response?.signature,
                            hasUserHandle: !!credential.response?.userHandle
                        });
                        
                        credential = {
                            id: credential.id,
                            rawId: arrayBufferToBase64Url(credential.rawId),
                            response: {
                                authenticatorData: arrayBufferToBase64Url(credential.response.authenticatorData),
                                clientDataJSON: arrayBufferToBase64Url(credential.response.clientDataJSON),
                                signature: arrayBufferToBase64Url(credential.response.signature),
                                userHandle: credential.response.userHandle ? arrayBufferToBase64Url(credential.response.userHandle) : null
                            },
                            type: credential.type
                        };
                        
                        console.log("[PasskeyAuth] Credential converted", {
                            id: credential.id,
                            rawIdLength: credential.rawId?.length,
                            hasUserHandle: !!credential.response?.userHandle
                        });
                    }
                }

                if (credential) {
                    console.log("[PasskeyAuth] Processing credential for transmission", {
                        jsonWebAuthnSupport: jsonWebAuthnSupport,
                        hasToJSON: jsonWebAuthnSupport && typeof credential.toJSON === "function"
                    });
                    
                    // Convert credential to JSON format for transmission
                    const credentialJson = jsonWebAuthnSupport && credential.toJSON ?
                        credential.toJSON() :
                        credential;

                    console.log("[PasskeyAuth] Pushing verify_authentication event", {
                        hasCredentialJson: !!credentialJson,
                        credentialJsonKeys: credentialJson ? Object.keys(credentialJson) : null,
                        hasResponse: !!credentialJson?.response,
                        hasUserHandle: !!credentialJson?.response?.userHandle
                    });

                    // Push the result back to the LiveView
                    this.pushEvent("verify_authentication", credentialJson);
                    console.log("[PasskeyAuth] verify_authentication event pushed successfully");
                } else {
                    console.warn("[PasskeyAuth] No credential returned from navigator.credentials.get()");
                }
            } catch (error) {
                console.error("[PasskeyAuth] Passkey authentication failed", {
                    error: error,
                    errorName: error.name,
                    errorMessage: error.message,
                    errorStack: error.stack
                });

                // Push error event to LiveView
                const errorData = {
                    error: error.name || "UnknownError",
                    message: error.message || "Authentication failed"
                };
                
                console.log("[PasskeyAuth] Pushing passkey_auth_error event", errorData);
                this.pushEvent("passkey_auth_error", errorData);
                console.log("[PasskeyAuth] passkey_auth_error event pushed");
            }
        });
        
        console.log("[PasskeyAuth] Hook setup complete - all event handlers registered");
    }
};

// Helper functions for Base64 URL encoding/decoding (for older browsers)
function base64UrlToArrayBuffer(base64url) {
    // Convert base64url to base64
    let base64 = base64url.replace(/-/g, '+').replace(/_/g, '/');

    // Add padding if needed
    while (base64.length % 4) {
        base64 += '=';
    }

    // Decode base64 to binary string
    const binaryString = atob(base64);

    // Convert binary string to ArrayBuffer
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
        bytes[i] = binaryString.charCodeAt(i);
    }

    return bytes.buffer;
}

function arrayBufferToBase64Url(arrayBuffer) {
    // Convert ArrayBuffer to Uint8Array
    const bytes = new Uint8Array(arrayBuffer);

    // Convert to binary string
    let binary = '';
    for (let i = 0; i < bytes.length; i++) {
        binary += String.fromCharCode(bytes[i]);
    }

    // Encode to base64
    const base64 = btoa(binary);

    // Convert base64 to base64url
    return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

export default PasskeyAuth;