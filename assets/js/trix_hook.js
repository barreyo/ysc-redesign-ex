
import Trix from '../vendor/trix'

module.exports = {
    mounted() {
        window.Trix = Trix;
    },

    updated() {
    }
}