let StripeInput = {
  mounted() {
    const clientSecret = this.el.dataset.clientsecret;
    const stripe = Stripe(this.el.dataset.publickey);

    const appearance = {};
    const options = { layout: "accordion" };
    const elements = stripe.elements({ clientSecret, appearance });
    const paymentElement = elements.create("payment", options);
    paymentElement.mount("#payment-element");

    const returnURL = this.el.dataset.returnurl;
    const submitURL = this.el.dataset.submiturl;

    console.log("returnURL", returnURL);
    console.log("submitURL", submitURL);

    submitButton = document.getElementById("submit");

    this.el.addEventListener("submit", async (event) => {
      event.preventDefault();

      submitButton.disabled = true;
      submitButton.classList.add("phx-submit-loading");

      const { error, setupIntent } = await stripe.confirmSetup({
        elements,
        redirect: "if_required",
        confirmParams: {
          return_url: returnURL,
        },
      });

      console.log("setupIntent", setupIntent);

      if (error) {
        // handle error
        console.error(error);
        return;
      }

      this.pushEvent("payment-method-set", {
        payment_method_id: setupIntent.payment_method,
      });
    });
  },
};

export default StripeInput;
