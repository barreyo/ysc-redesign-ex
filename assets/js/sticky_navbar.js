export default StickyNavbar = {
    mounted() {
        const navbar = this.el
        var sticky = navbar.offsetTop

        function stickyScroll() {
            if (window.scrollY >= sticky) {
                navbar.classList.add("fixed")
                navbar.classList.add("shadow-lg")
            } else {
                navbar.classList.remove("fixed")
                navbar.classList.remove("shadow-lg")
            }
        }

        window.onscroll = function () {
            stickyScroll()
        }
    },
};
