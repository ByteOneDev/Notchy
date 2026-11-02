import CoreLocation
import SwiftUI

/// Weather from Open-Meteo (free, no API key), at the current location or a chosen city.
@MainActor
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherService()

    struct RainSlot: Identifiable, Equatable {
        let date: Date
        /// Millimeters over the quarter hour.
        let amount: Double
        var id: Date { date }
        var isWet: Bool { amount >= 0.1 }
    }

    struct Hour: Identifiable, Equatable {
        let date: Date
        let temperature: Double
        let code: Int
        let isDay: Bool
        var id: Date { date }
        var symbol: String { WeatherService.symbol(for: code, isDay: isDay) }
    }

    struct Current: Equatable {
        let temperature: Double
        let code: Int
        let isDay: Bool
        let high: Double
        let low: Double

        var symbol: String { WeatherService.symbol(for: code, isDay: isDay) }
        var temperatureText: String { WeatherService.format(temperature) }
    }

    @Published private(set) var current: Current?
    @Published private(set) var cityName = ""
    /// Precipitation for the next three hours, by quarter hour.
    @Published private(set) var rainSlots: [RainSlot] = []
    /// The coming hours.
    @Published private(set) var hourly: [Hour] = []
    private let locationManager = CLLocationManager()
    private var timer: Timer?
    private var rainAnnounced = false

    func start() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        refresh()
        // Every 15 minutes, so the rain alert comes early enough.
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { _ in
            MainActor.assumeIsolated { WeatherService.shared.refresh() }
        }
    }

    func refresh() {
        let settings = AppSettings.shared
        guard settings.weatherEnabled else { return }
        if settings.weatherUsesLocation {
            switch locationManager.authorizationStatus {
            case .notDetermined: locationManager.requestWhenInUseAuthorization()
            case .authorized, .authorizedAlways: locationManager.requestLocation()
            default: fetch(latitude: settings.weatherLatitude, longitude: settings.weatherLongitude, city: settings.weatherCity)
            }
        } else {
            fetch(latitude: settings.weatherLatitude, longitude: settings.weatherLongitude, city: settings.weatherCity)
        }
    }

    /// Looks a city up and makes it the weather location.
    func setCity(_ query: String) async -> Bool {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [URLQueryItem(name: "name", value: query), URLQueryItem(name: "count", value: "1"),
                                 URLQueryItem(name: "language", value: Loc.language.rawValue)]
        guard let (data, _) = try? await URLSession.shared.data(from: components.url!),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = (json["results"] as? [[String: Any]])?.first,
              let lat = result["latitude"] as? Double, let lon = result["longitude"] as? Double else { return false }
        let settings = AppSettings.shared
        settings.weatherCity = result["name"] as? String ?? query
        settings.weatherLatitude = lat
        settings.weatherLongitude = lon
        settings.weatherUsesLocation = false
        fetch(latitude: lat, longitude: lon, city: settings.weatherCity)
        return true
    }

    private func fetch(latitude: Double, longitude: Double, city: String?) {
        Task {
            var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            components.queryItems = [
                URLQueryItem(name: "latitude", value: String(latitude)),
                URLQueryItem(name: "longitude", value: String(longitude)),
                URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
                URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
                URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
                URLQueryItem(name: "forecast_hours", value: "10"),
                URLQueryItem(name: "minutely_15", value: "precipitation"),
                URLQueryItem(name: "forecast_minutely_15", value: "14"),
                URLQueryItem(name: "forecast_days", value: "1"),
                URLQueryItem(name: "timezone", value: "auto"),
                URLQueryItem(name: "timeformat", value: "unixtime"),
            ]
            guard let (data, _) = try? await URLSession.shared.data(from: components.url!),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = json["current"] as? [String: Any],
                  let daily = json["daily"] as? [String: Any] else { return }
            checkRain(json["minutely_15"] as? [String: Any])
            if let hours = json["hourly"] as? [String: Any], let times = hours["time"] as? [Double],
               let temperatures = hours["temperature_2m"] as? [Double], let codes = hours["weather_code"] as? [Int],
               let days = hours["is_day"] as? [Int], times.count == temperatures.count,
               times.count == codes.count, times.count == days.count {
                let now = Date.now.timeIntervalSince1970
                hourly = times.indices.filter { times[$0] > now }.map {
                    Hour(date: Date(timeIntervalSince1970: times[$0]), temperature: temperatures[$0], code: codes[$0], isDay: days[$0] == 1)
                }
            }
            self.current = Current(
                temperature: current["temperature_2m"] as? Double ?? 0,
                code: current["weather_code"] as? Int ?? 0,
                isDay: (current["is_day"] as? Int ?? 1) == 1,
                high: (daily["temperature_2m_max"] as? [Double])?.first ?? 0,
                low: (daily["temperature_2m_min"] as? [Double])?.first ?? 0
            )
            if let city { cityName = city }
        }
    }

    /// Announces rain expected within the next hour, once per dry spell.
    private func checkRain(_ minutely: [String: Any]?) {
        guard let times = minutely?["time"] as? [Double],
              let amounts = minutely?["precipitation"] as? [Double], times.count == amounts.count else { return }
        let now = Date.now.timeIntervalSince1970
        rainSlots = zip(times, amounts).filter { $0.0 + 15 * 60 > now }.prefix(12)
            .map { RainSlot(date: Date(timeIntervalSince1970: $0.0), amount: $0.1) }
        let upcoming = zip(times, amounts).filter { $0.0 + 15 * 60 > now && $0.0 < now + 75 * 60 }
        let wet = upcoming.filter { $0.1 >= 0.1 }
        guard let first = wet.first else {
            rainAnnounced = false
            return
        }
        guard AppSettings.shared.rainAlert, !rainAnnounced else { return }
        rainAnnounced = true
        let minutes = max(0, Int(((first.0 - now) / 60).rounded()))
        let heavy = wet.contains { $0.1 >= 1.5 }
        LiveActivityCenter.shared.show(.rain(minutes: minutes, heavy: heavy), duration: 5)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
            self.fetch(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                       city: placemark?.locality ?? AppSettings.shared.weatherCity)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            let settings = AppSettings.shared
            self.fetch(latitude: settings.weatherLatitude, longitude: settings.weatherLongitude, city: settings.weatherCity)
        }
    }

    nonisolated static func format(_ celsius: Double) -> String {
        let fahrenheit = UserDefaults.standard.string(forKey: "temperatureUnit") == TemperatureUnit.fahrenheit.rawValue
        let value = fahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°"
    }

    /// WMO weather code → SF Symbol.
    nonisolated static func symbol(for code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func description(for code: Int) -> String {
        switch code {
        case 0: L("weather.clear")
        case 1, 2: L("weather.partly")
        case 3: L("weather.cloudy")
        case 45, 48: L("weather.fog")
        case 51...57: L("weather.drizzle")
        case 61...67, 80...82: L("weather.rain")
        case 71...77, 85, 86: L("weather.snow")
        case 95...99: L("weather.storm")
        default: ""
        }
    }
}

/// Now on the left, the coming hours below. Wide when it is alone on the home panel.
struct WeatherWidget: View {
    var wide = false
    @ObservedObject private var weather = WeatherService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(widget: .weather) {
                Text(weather.cityName).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
            }
            if let current = weather.current {
                HStack(spacing: 10) {
                    Image(systemName: current.symbol).symbolRenderingMode(.multicolor).font(.system(size: wide ? 34 : 28))
                    Text(current.temperatureText).font(.system(size: wide ? 36 : 30, weight: .semibold)).fixedSize()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(WeatherService.description(for: current.code)).font(.system(size: 12, weight: .medium))
                        Text("↑ \(WeatherService.format(current.high))  ↓ \(WeatherService.format(current.low))")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    ForEach(weather.hourly.prefix(wide ? 10 : 4)) { hour in
                        VStack(spacing: 4) {
                            Text(hour.date.formatted(.dateTime.hour(.twoDigits(amPM: .abbreviated)).locale(Loc.locale)))
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1).fixedSize()
                            Image(systemName: hour.symbol).symbolRenderingMode(.multicolor).font(.system(size: 13))
                                .frame(height: 16)
                            Text(WeatherService.format(hour.temperature)).font(.system(size: 11, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
