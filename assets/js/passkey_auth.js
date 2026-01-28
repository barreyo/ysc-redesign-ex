/**
 * PasskeyAuth Hook
 * 
 * Handles WebAuthn/Passkey authentication using the browser's native API.
 * Uses builtin browser functionality (parseRequestOptionsFromJSON) when available.
 */
const PasskeyAuth = {
    mounted() {
        // Check if WebAuthn is supported
        if (!window.PublicKeyCredential) {
            console.warn("WebAuthn/Passkey not supported in this browser");
            return;
        }

        // Listen for authentication challenge from LiveView
        this.handleEvent("create_authentication_challenge", async ({ options }) => {
            try {
                // Check if browser supports JSON-based WebAuthn API
                const jsonWebAuthnSupport = !!window.PublicKeyCredential?.parseRequestOptionsFromJSON;

                let credential;

                if (jsonWebAuthnSupport) {
                    // Use modern JSON-based API (Chrome 108+, Safari 16.4+, Firefox 119+)
                    const publicKey = PublicKeyCredential.parseRequestOptionsFromJSON({ publicKey: options });
                    credential = await navigator.credentials.get({ publicKey });
                } else {
                    // Fallback to traditional API (requires manual Base64 encoding/decoding)
                    // Convert base64url strings to ArrayBuffer
                    const publicKey = {
                        ...options,
                        challenge: base64UrlToArrayBuffer(options.challenge)
                    };

                    // Only include allowCredentials if it exists (non-discoverable mode)
                    // If omitted, browser will show native account picker (discoverable credentials)
                    if (options.allowCredentials && options.allowCredentials.length > 0) {
                        publicKey.allowCredentials = options.allowCredentials.map(cred => ({
                            ...cred,
                            id: base64UrlToArrayBuffer(cred.id)
                        }));
                    }

                    credential = await navigator.credentials.get({ publicKey });

                    // Convert ArrayBuffers back to base64url strings
                    if (credential) {
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
                    }
                }

                if (credential) {
                    // Convert credential to JSON format for transmission
                    const credentialJson = jsonWebAuthnSupport && credential.toJSON 
                        ? credential.toJSON() 
                        : credential;

                    // Push the result back to the LiveView
                    this.pushEvent("verify_authentication", credentialJson);
                }
            } catch (error) {
                console.error("Passkey authentication failed:", error);
                
                // Push error event to LiveView
                this.pushEvent("passkey_auth_error", { 
                    error: error.name || "UnknownError",
                    message: error.message || "Authentication failed"
                });
            }
        });
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
