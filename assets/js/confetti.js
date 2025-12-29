// Confetti hook for celebratory moments
// Uses canvas-confetti library (loaded via CDN)
const Confetti = {
    mounted() {
        // Only fire confetti if the data attribute indicates it should
        const showConfetti = this.el.dataset.showConfetti === 'true';
        console.log('[Confetti] Hook mounted, showConfetti:', showConfetti, 'data attribute:', this.el.dataset.showConfetti);
        if (showConfetti) {
            // Wait for confetti library to load (it's loaded with defer)
            this.waitForConfetti();
        }
    },

    waitForConfetti() {
        // Check if confetti library is available (it's loaded as a global)
        if (typeof window.confetti !== 'undefined') {
            console.log('[Confetti] Library loaded, firing confetti');
            this.fireConfetti();
        } else {
            // If library not loaded yet, wait and try again (max 50 attempts = 5 seconds)
            if (!this.attempts) this.attempts = 0;
            this.attempts++;
            if (this.attempts < 50) {
                setTimeout(() => {
                    this.waitForConfetti();
                }, 100);
            } else {
                console.error('[Confetti] Library failed to load after 5 seconds');
            }
        }
    },

    fireConfetti() {
        console.log('[Confetti] Firing confetti animation');
        // Scandinavian "Midsummer Petals" style
        // Muted Nordic palette: soft white, cream, pale yellow, light blue
        const nordicColors = ['#f8fafc', '#bae6fd', '#fef08a', '#e2e8f0'];

        // Gentle drift from top - multiple small bursts across the top
        // Creates a calm, organic "petal fall" effect
        const burstCount = 5;
        const burstInterval = 300; // Space out the bursts for a gentle cascade

        for (let i = 0; i < burstCount; i++) {
            setTimeout(() => {
                try {
                    // Use only well-supported canvas-confetti options
                    const confettiFn = window.confetti || (window.confetti && window.confetti.default);

                    if (typeof confettiFn === 'function') {
                        confettiFn({
                            particleCount: 30,
                            spread: 70,
                            origin: {
                                x: Math.random() * 0.6 + 0.2, // Spread across 20% to 80% of screen width
                                y: 0.1 // Start from top, like petals drifting down
                            },
                            colors: nordicColors,
                            gravity: 0.6, // Slower, more gentle fall - like a light breeze
                            ticks: 300, // Longer animation for calm, drifting effect
                            scalar: 0.8, // Slightly smaller particles for subtlety
                            startVelocity: 15 // Lower initial velocity for gentle descent
                        });
                        console.log(`[Confetti] Burst ${i + 1} fired`);
                    } else {
                        console.error('[Confetti] Function not available:', typeof confettiFn, 'window.confetti:', typeof window.confetti);
                    }
                } catch (error) {
                    console.error('[Confetti] Error firing confetti:', error);
                }
            }, i * burstInterval);
        }
    }
};

export default Confetti;