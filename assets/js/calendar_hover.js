const CalendarHover = {
  mounted() {
    this.handleMouseMove = (e) => {
      const cell = e.target.closest('[data-date]');
      if (cell && cell.dataset.date) {
        const date = cell.dataset.date;
        const selectionType = cell.dataset.selectionType;
        const roomId = cell.dataset.roomId;

        if (selectionType) {
          const params = {
            date: date,
            selection_type: selectionType
          };

          if (roomId) {
            params.room_id = roomId;
          }

          this.pushEvent("hover-date", params);
        }
      }
    };

    this.handleMouseLeave = () => {
      this.pushEvent("clear-hover");
    };

    this.el.addEventListener("mousemove", this.handleMouseMove);
    this.el.addEventListener("mouseleave", this.handleMouseLeave);
  },

  destroyed() {
    if (this.handleMouseMove) {
      this.el.removeEventListener("mousemove", this.handleMouseMove);
    }
    if (this.handleMouseLeave) {
      this.el.removeEventListener("mouseleave", this.handleMouseLeave);
    }
  }
};

export default CalendarHover;

