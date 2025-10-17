// Stripe Elements Hook for Phoenix LiveView

let stripePromise = null;

const getStripe = () => {
    if (!stripePromise && window.Stripe) {
        stripePromise = window.Stripe(window.stripePublishableKey);
    }
    return stripePromise;
};

const StripeElements = {
    mounted() {
        this.initializeStripe();
    },

    updated() {
        // Re-initialize if the client secret changes
        const newClientSecret = this.el.dataset.clientSecret;
        if (newClientSecret && newClientSecret !== this.clientSecret) {
            this.initializeStripe();
        }
    },

    async initializeStripe() {
        const clientSecret = this.el.dataset.clientSecret;

        if (!clientSecret) {
            console.error('No client secret provided');
            return;
        }

        this.clientSecret = clientSecret;

        try {
            // Wait for Stripe to be available
            let attempts = 0;
            while (!window.Stripe && attempts < 50) {
                await new Promise(resolve => setTimeout(resolve, 100));
                attempts++;
            }

            if (!window.Stripe) {
                console.error('Stripe not available');
                this.showMessage('Payment system not ready. Please refresh and try again.');
                return;
            }

            const stripe = getStripe();

            if (!stripe) {
                console.error('Failed to initialize Stripe');
                return;
            }

            this.stripe = stripe;

            // Create or get the payment element
            if (!this.elements) {
                this.elements = stripe.elements({
                    clientSecret: clientSecret,
                    appearance: {
                        theme: 'stripe',
                        variables: {
                            colorPrimary: '#3b82f6',
                            colorBackground: '#ffffff',
                            colorText: '#1f2937',
                            colorDanger: '#ef4444',
                            fontFamily: 'system-ui, sans-serif',
                            spacingUnit: '4px',
                            borderRadius: '8px',
                        }
                    }
                });

                this.paymentElement = this.elements.create('payment', {
                    layout: 'tabs'
                });

                this.paymentElement.mount('#payment-element');
            }

            // Handle form submission
            this.handleSubmit = this.handleSubmit.bind(this);
            const submitButton = document.getElementById('submit-payment');
            if (submitButton) {
                submitButton.addEventListener('click', this.handleSubmit);
            }

        } catch (error) {
            console.error('Error initializing Stripe Elements:', error);
            this.showMessage('Failed to initialize payment form. Please refresh and try again.');
        }
    },

    async handleSubmit(event) {
        event.preventDefault();

        const submitButton = document.getElementById('submit-payment');
        const messageDiv = document.getElementById('payment-message');

        if (!this.stripe || !this.paymentElement) {
            this.showMessage('Payment form not ready. Please try again.');
            return;
        }

        // Disable the submit button
        submitButton.disabled = true;
        submitButton.textContent = 'Processing...';

        try {
            const { error } = await this.stripe.confirmPayment({
                elements: this.elements,
                confirmParams: {
                    return_url: `${window.location.origin}/payment/success`,
                },
                redirect: 'if_required'
            });

            if (error) {
                // Show error to customer
                this.showMessage(error.message);
                submitButton.disabled = false;
                submitButton.textContent = 'Pay';
            } else {
                // Payment succeeded
                this.showMessage('Payment successful! Processing your order...');

                // Notify the LiveView that payment was successful
                this.pushEvent('payment-success', {
                    payment_intent_id: this.clientSecret.split('_secret_')[0]
                });
            }
        } catch (err) {
            console.error('Payment confirmation error:', err);
            this.showMessage('An unexpected error occurred. Please try again.');
            submitButton.disabled = false;
            submitButton.textContent = 'Pay';
        }
    },

    showMessage(message) {
        const messageDiv = document.getElementById('payment-message');
        if (messageDiv) {
            messageDiv.textContent = message;
            messageDiv.classList.remove('hidden');

            // Hide message after 5 seconds
            setTimeout(() => {
                messageDiv.classList.add('hidden');
            }, 5000);
        }
    },

    destroyed() {
        // Clean up event listeners
        const submitButton = document.getElementById('submit-payment');
        if (submitButton) {
            submitButton.removeEventListener('click', this.handleSubmit);
        }

        // Unmount Stripe Elements
        if (this.paymentElement) {
            this.paymentElement.unmount();
        }
    }
};

export default StripeElements;