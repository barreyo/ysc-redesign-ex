export default HeroMode = {
    mounted() {
        this.enableHeroMode();
    },

    destroyed() {
        this.disableHeroMode();
    },

    enableHeroMode() {
        const header = document.getElementById("site-header");
        if (header) {
            header.classList.add("hero-mode");
        }
    },

    disableHeroMode() {
        const header = document.getElementById("site-header");
        if (header) {
            header.classList.remove("hero-mode");
        }
    }
};