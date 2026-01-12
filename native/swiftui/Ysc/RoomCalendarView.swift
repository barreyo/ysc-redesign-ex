//
//  RoomCalendarView.swift
//  Ysc
//
//  Custom calendar component for displaying room bookings in a Gantt-style timeline

import SwiftUI
import LiveViewNative

// PreferenceKey for tracking scroll offset
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// Helper view to synchronize horizontal scrolling between header and body
struct SynchronizedScrollView<HeaderContent: View, BodyContent: View>: View {
    let headerContent: () -> HeaderContent
    let bodyContent: () -> BodyContent

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                // Date Header Row
                headerContent()

                // Room Rows with Bookings - vertical scrolling only
                ScrollView(.vertical, showsIndicators: true) {
                    bodyContent()
                }
            }
        }
    }
}

// Data models for the calendar
struct Room: Codable {
    let id: String  // ULID as string
    let name: String
}

struct Booking: Codable {
    let id: String  // ULID as string
    let userName: String
    let checkinDate: String  // ISO8601 date string
    let checkoutDate: String // ISO8601 date string
    let checkedIn: Bool
    let carInfo: String?  // Optional car information
    let guestsCount: Int  // Number of adults
    let childrenCount: Int  // Number of children
}

struct CalendarData: Codable {
    let rooms: [Room]
    let calendarDates: [String]  // ISO8601 date strings
    let bookingsByRoom: [String: [Booking]]  // room_id as string key
    let today: String  // ISO8601 date string
    let calendarStartDate: String
    let calendarEndDate: String
}

@LiveElement
struct RoomCalendar<Root: RootRegistry>: View {
    let element: ElementNode

    // Parse data from element attributes
    private var calendarData: CalendarData? {
        // Debug: Check what we're getting
        let attrValue = element.attributeValue(for: "data")

        guard let dataAttr = attrValue as? String else {
            print("[RoomCalendar] Attribute 'data' is not a String. Type: \(type(of: attrValue)), Value: \(String(describing: attrValue))")
            return nil
        }

        // Decode HTML entities (LiveView Native HTML-encodes JSON attributes)
        // Must decode in order: &amp; first, then others
        let decodedString = dataAttr
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#x2F;", with: "/")

        guard let data = decodedString.data(using: String.Encoding.utf8) else {
            print("[RoomCalendar] Failed to convert string to Data. String length: \(decodedString.count)")
            print("[RoomCalendar] First 200 chars: \(String(decodedString.prefix(200)))")
            return nil
        }

        do {
            let decoded = try JSONDecoder().decode(CalendarData.self, from: data)
            print("[RoomCalendar] Successfully decoded calendar data. Rooms: \(decoded.rooms.count), Dates: \(decoded.calendarDates.count)")
            return decoded
        } catch {
            print("[RoomCalendar] JSON decode error: \(error)")
            if let jsonString = String(data: data, encoding: .utf8) {
                print("[RoomCalendar] JSON string (first 500 chars): \(String(jsonString.prefix(500)))")
            }
            return nil
        }
    }

    private let dayWidth: CGFloat = 80
    private let rowHeight: CGFloat = 80
    private let headerHeight: CGFloat = 60
    private let roomColumnWidth: CGFloat = 140

    var body: some View {
        if let data = calendarData {
            calendarView(data: data)
        } else {
            VStack(spacing: 12) {
                Text("Loading calendar...")
                    .foregroundColor(.secondary)

                // Debug info
                if let attrValue = element.attributeValue(for: "data") {
                    Text("Attribute type: \(String(describing: type(of: attrValue)))")
                        .font(.caption)
                        .foregroundColor(.red)

                    if let str = attrValue as? String, !str.isEmpty {
                        Text("String length: \(str.count)")
                            .font(.caption)
                            .foregroundColor(.red)

                        if str.count > 0 {
                            Text("First 100 chars: \(String(str.prefix(100)))")
                                .font(.caption)
                                .foregroundColor(.red)
                                .lineLimit(3)
                        }
                    }
                } else {
                    Text("Attribute 'data' is nil")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func calendarView(data: CalendarData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Who Am I Staying With?")
                    .font(.system(size: 32, weight: .bold))

                Text(dateRangeText(startDate: data.calendarStartDate, endDate: data.calendarEndDate))
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)

            // Legend
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.green)
                
                Text("Checked in")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)

            // Calendar Grid
            HStack(alignment: VerticalAlignment.top, spacing: 0) {
                // Fixed Left Column: Room Names
                VStack(alignment: .leading, spacing: 0) {
                    // Room Header
                    HStack(alignment: .center) {
                        Text("Room")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 16)
                    .frame(height: headerHeight)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(Color(uiColor: .separator)),
                        alignment: .bottom
                    )

                    // Room Names List
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(data.rooms, id: \.id) { room in
                                HStack(alignment: .center) {
                                    Text(room.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.primary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: rowHeight)
                                .overlay(
                                    Rectangle()
                                        .frame(height: 1)
                                        .foregroundColor(Color(uiColor: .separator)),
                                    alignment: .bottom
                                )
                            }
                        }
                    }
                }
                .frame(width: roomColumnWidth)
                .background(Color(uiColor: .secondarySystemBackground))

                // Scrollable Right Area: Date Columns
                SynchronizedScrollView(
                    headerContent: {
                        HStack(alignment: .center, spacing: 0) {
                            ForEach(data.calendarDates, id: \.self) { dateStr in
                                dateHeaderCell(
                                    dateStr: dateStr,
                                    isToday: dateStr == data.today
                                )
                            }
                        }
                    },
                    bodyContent: {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(data.rooms, id: \.id) { room in
                                roomRow(
                                    room: room,
                                    dates: data.calendarDates,
                                    bookings: data.bookingsByRoom[room.id] ?? [],
                                    startDate: data.calendarStartDate,
                                    today: data.today
                                )
                            }
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func dateHeaderCell(dateStr: String, isToday: Bool) -> some View {
        let date = parseDate(dateStr) ?? Date()
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles") // Use PST/PDT
        formatter.dateFormat = "EEE"
        let dayName = formatter.string(from: date)
        formatter.dateFormat = "MM/dd"
        let dateFormatted = formatter.string(from: date)

        return VStack(alignment: .center, spacing: 4) {
            Text(dayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isToday ? .blue : .secondary)

            Text(dateFormatted)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isToday ? .blue : .primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(width: dayWidth, height: headerHeight)
        .background(isToday ? Color.blue.opacity(0.15) : Color(uiColor: .secondarySystemBackground))
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color(uiColor: .separator)),
            alignment: .trailing
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(uiColor: .separator)),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private func roomRow(
        room: Room,
        dates: [String],
        bookings: [Booking],
        startDate: String,
        today: String
    ) -> some View {
        ZStack(alignment: .topLeading) {
            // Background grid cells
            HStack(alignment: .center, spacing: 0) {
                ForEach(dates, id: \.self) { dateStr in
                    let isToday = dateStr == today
                    Rectangle()
                        .fill(isToday ? Color.blue.opacity(0.08) : Color.white)
                        .frame(width: dayWidth, height: rowHeight)
                        .overlay(
                            Rectangle()
                                .frame(width: 1)
                                .foregroundColor(Color(uiColor: .separator)),
                            alignment: .trailing
                        )
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(Color(uiColor: .separator)),
                            alignment: .bottom
                        )
                }
            }

            // Booking bars
            ForEach(bookings, id: \.id) { booking in
                bookingBar(
                    booking: booking,
                    dates: dates,
                    startDate: startDate
                )
            }
        }
        .frame(height: rowHeight)
    }

    private func bookingBar(
        booking: Booking,
        dates: [String],
        startDate: String
    ) -> some View {
        // Normalize date strings by trimming whitespace
        let checkinDateStr = booking.checkinDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let checkoutDateStr = booking.checkoutDate.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find the index by comparing normalized dates
        let checkinIdx = dates.firstIndex { $0.trimmingCharacters(in: .whitespacesAndNewlines) == checkinDateStr } ?? -1
        let checkoutIdx = dates.firstIndex { $0.trimmingCharacters(in: .whitespacesAndNewlines) == checkoutDateStr } ?? -1

        // If checkout is on the first date of the calendar, don't render (booking is already over)
        if let firstDate = dates.first, checkoutDateStr == firstDate.trimmingCharacters(in: .whitespacesAndNewlines) {
            return AnyView(EmptyView())
        }

        // Handle bookings that start before or end after the visible calendar range
        // If checkout is not in range, don't render (booking is completely outside)
        guard checkoutIdx >= 0 else {
            return AnyView(EmptyView())
        }

        let totalDays = dates.count
        // If check-in is before the calendar start, clamp to 0 (start of visible range)
        // If check-in is not found but checkout is, assume booking started before calendar
        let clampedCheckinIdx: Int
        if checkinIdx < 0 {
            // Check-in date not in calendar - if checkout is in range, booking started before
            // Start the bar at the beginning of the visible range
            clampedCheckinIdx = 0
        } else {
            clampedCheckinIdx = min(checkinIdx, totalDays - 1)
        }

        // For checkout, we want to show it ending at the middle of the checkout day
        // (even though checkout is technically exclusive, we show it visually)
        let clampedCheckoutIdx = max(0, min(checkoutIdx, totalDays - 1))

        // Ensure checkout is after check-in (at least visually)
        guard clampedCheckoutIdx >= clampedCheckinIdx else {
            return AnyView(EmptyView())
        }

        // Start at the middle of the check-in day, end at the middle of the checkout day
        // This prevents overlap for back-to-back bookings
        let startOffset = CGFloat(clampedCheckinIdx) * dayWidth + dayWidth / 2
        let endOffset = CGFloat(clampedCheckoutIdx) * dayWidth + dayWidth / 2

        // Ensure minimum width (at least half a day) for same-day bookings
        let barWidth = max(dayWidth / 2, endOffset - startOffset)

        // Debug logging
        print("[RoomCalendar] Booking '\(booking.userName)' - Check-in: \(checkinDateStr) (idx: \(checkinIdx) -> \(clampedCheckinIdx)), Checkout: \(checkoutDateStr) (idx: \(checkoutIdx) -> \(clampedCheckoutIdx))")
        print("[RoomCalendar] Offsets - Start: \(startOffset), End: \(endOffset), Width: \(barWidth)")
        if clampedCheckinIdx < dates.count && clampedCheckoutIdx < dates.count {
            print("[RoomCalendar] Renders on dates: \(dates[clampedCheckinIdx]) to \(dates[clampedCheckoutIdx])")
        }

        // Format dates for display
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "America/Los_Angeles") // Use PST/PDT
        dateFormatter.dateFormat = "MM/dd"

        let checkinStr: String
        let checkoutStr: String

        if let checkinDate = parseDate(booking.checkinDate),
           let checkoutDate = parseDate(booking.checkoutDate) {
            checkinStr = dateFormatter.string(from: checkinDate)
            checkoutStr = dateFormatter.string(from: checkoutDate)
        } else {
            // Fallback to raw date strings if parsing fails
            checkinStr = booking.checkinDate
            checkoutStr = booking.checkoutDate
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 3) { // Reduced spacing from 4 to 3
                HStack(alignment: .center, spacing: 4) {
                    Text(booking.userName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.blue)
                        .lineLimit(1)

                    if booking.checkedIn {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                    }

                    Spacer()
                }

                // Display date range with guest count on the same line
                let guestText = formatGuestCount(adults: booking.guestsCount, children: booking.childrenCount)
                let dateText = !guestText.isEmpty
                    ? "\(checkinStr) - \(checkoutStr) • \(guestText)"
                    : "\(checkinStr) - \(checkoutStr)"
                Text(dateText)
                    .font(.system(size: 11))
                    .foregroundColor(.blue.opacity(0.8))
                    .lineLimit(1)

                if let carInfo = booking.carInfo, !carInfo.isEmpty {
                    Text(carInfo)
                        .font(.system(size: 10))
                        .foregroundColor(.blue.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4) // Reduced from 6 to 4 to fit better
            .frame(width: barWidth, height: calculateBookingBarHeight(hasCarInfo: booking.carInfo != nil && !booking.carInfo!.isEmpty, hasGuests: booking.guestsCount > 0 || booking.childrenCount > 0), alignment: .leading)
            .background(Color.blue.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .offset(x: startOffset)
        )
    }

    // Helper functions
    private func formatGuestCount(adults: Int, children: Int) -> String {
        var parts: [String] = []

        if adults > 0 {
            if adults == 1 {
                parts.append("1 adult")
            } else {
                parts.append("\(adults) adults")
            }
        }

        if children > 0 {
            if children == 1 {
                parts.append("1 child")
            } else {
                parts.append("\(children) children")
            }
        }

        return parts.joined(separator: ", ")
    }

    private func calculateBookingBarHeight(hasCarInfo: Bool, hasGuests: Bool) -> CGFloat {
        // Calculate height based on content with reduced padding (4) and spacing (3):
        // - Vertical padding: 4 * 2 = 8
        // - Name line (font 13, semibold): ~18
        // - VStack spacing: 3
        // - Date line (font 11): ~16
        // - VStack spacing (if car info): 3
        // - Car info line (font 10, if present): ~14

        var height: CGFloat = 8 // Vertical padding (4 top + 4 bottom)
        height += 18 // Name line (font 13, semibold)
        height += 3 // VStack spacing
        height += 16 // Date range line (font 11)

        if hasCarInfo {
            height += 3 // VStack spacing before car info
            height += 14 // Car info line (font 10)
        }

        // Total: 8 + 18 + 3 + 16 = 45 (base) or 45 + 3 + 14 = 62 (with car)
        // Ensure it doesn't exceed row height (80) to prevent layout breaking
        return min(height, rowHeight - 2) // Leave 2 points margin for safety
    }

    private func parseDate(_ dateStr: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles") // Use PST/PDT
        return formatter.date(from: dateStr)
    }

    private func dateRangeText(startDate: String, endDate: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles") // Use PST/PDT
        formatter.dateFormat = "MMMM dd"

        guard let start = parseDate(startDate),
              let end = parseDate(endDate) else {
            return "\(startDate) - \(endDate)"
        }

        let startStr = formatter.string(from: start)
        formatter.dateFormat = "MMMM dd, yyyy"
        let endStr = formatter.string(from: end)

        return "\(startStr) - \(endStr)"
    }
}

// The Addons namespace is used by LiveView Native to register custom components
extension Addons {
    @Addon
    struct RoomCalendarView<Root: RootRegistry> {
        enum TagName: String {
            case roomCalendar = "RoomCalendar"
        }

        @ViewBuilder
        public static func lookup(_ name: TagName, element: ElementNode) -> some View {
            switch name {
            case .roomCalendar:
                RoomCalendar<Root>(element: element)
            }
        }
    }
}
