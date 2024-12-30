let MoneyInput = {
  mounted() {
    this.el.addEventListener("input", (e) => {
      // Remove any non-numeric characters except decimal point
      let value = e.target.value.replace(/[^\d.]/g, "");

      // Ensure only one decimal point
      const decimalPoints = value.match(/\./g);
      if (decimalPoints && decimalPoints.length > 1) {
        const parts = value.split(".");
        value = parts[0] + "." + parts.slice(1).join("");
      }

      // Limit to two decimal places
      const parts = value.split(".");
      if (parts[1] && parts[1].length > 2) {
        parts[1] = parts[1].substring(0, 2);
        value = parts.join(".");
      }

      // Optional: Format with thousand separators as user types
      // Only format the part before the decimal
      if (parts[0].length > 3) {
        parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
        value = parts.join(".");
      }

      e.target.value = value;
    });

    // Remove formatting when focusing (optional)
    this.el.addEventListener("focus", (e) => {
      const value = e.target.value.replace(/,/g, "");
      e.target.value = value;
    });

    // Reapply formatting when leaving field (optional)
    this.el.addEventListener("blur", (e) => {
      if (e.target.value) {
        const num = parseFloat(e.target.value.replace(/,/g, ""));
        if (!isNaN(num)) {
          const parts = num.toFixed(2).split(".");
          parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",");
          e.target.value = parts.join(".");
        }
      }
    });
  },
};

export default MoneyInput;
