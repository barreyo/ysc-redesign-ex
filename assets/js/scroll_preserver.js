let ScrollPreserver = {
    mounted() {
        this.gallery = this.el;
        this.restoreFromURL();

        // Listen for before-navigate events to capture scroll position
        this.handleBeforeNavigate = (event) => {
            const scrollTop = window.scrollY || document.documentElement.scrollTop;
            const urlParams = new URLSearchParams(window.location.search);
            const yearParam = urlParams.get('year');

            // Get the target URL from the event
            const targetUrl = event.detail?.to;
            if (!targetUrl) return;

            try {
                // Parse the target URL
                const url = new URL(targetUrl, window.location.origin);

                // Add scroll position to query params
                url.searchParams.set('scroll', scrollTop.toString());

                // Preserve year if it exists
                if (yearParam) {
                    url.searchParams.set('year', yearParam);
                }

                // Update the navigation target
                event.detail.to = url.pathname + url.search;
            } catch (e) {
                console.warn('Failed to intercept navigation:', e);
            }
        };

        // Listen for phx:before-navigate events
        window.addEventListener('phx:before-navigate', this.handleBeforeNavigate);
    },

    destroyed() {
        // Clean up event listener
        if (this.handleBeforeNavigate) {
            window.removeEventListener('phx:before-navigate', this.handleBeforeNavigate);
        }
    },

    updated() {
        // Restore scroll position after DOM updates if URL has scroll param
        this.restoreFromURL();
    },

    saveScrollPosition(payload) {
        const scrollTop = window.scrollY || document.documentElement.scrollTop;
        const selectedYear = payload?.year !== null && payload?.year !== undefined ? payload?.year : null;

        // Build URL with state parameters
        const url = new URL(window.location.href);
        url.searchParams.set('scroll', scrollTop.toString());
        if (selectedYear !== null && selectedYear !== undefined) {
            url.searchParams.set('year', selectedYear.toString());
        } else {
            url.searchParams.delete('year');
        }

        // Update URL without navigating (this happens before navigation to modal)
        // The URL will be read when returning from modal
        window.history.replaceState(null, '', url.toString());
    },

    restoreFromURL() {
        const urlParams = new URLSearchParams(window.location.search);
        const scrollParam = urlParams.get('scroll');
        const yearParam = urlParams.get('year');

        // Restore scroll position if present
        if (scrollParam) {
            const scrollTop = parseInt(scrollParam, 10);
            if (!isNaN(scrollTop)) {
                // Use requestAnimationFrame to ensure DOM is ready
                requestAnimationFrame(() => {
                    window.scrollTo({
                        top: scrollTop,
                        behavior: 'auto'
                    });
                });
            }
        }
    }
};

export default ScrollPreserver;