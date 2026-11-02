import CoreLocation
import SwiftUI

/// Weather from Open-Meteo (free, no API key), at the current location or a chosen city.
@MainActor
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherService()

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
    private let locationManager = CLLocationManager()
    private var timer: Timer?
    private var coordinate: CLLocationCoordinate2D?

    func start() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { _ in
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
                URLQueryItem(name: "forecast_days", value: "1"),
                URLQueryItem(name: "timezone", value: "auto"),
            ]
            guard let (data, _) = try? await URLSession.shared.data(from: components.url!),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = json["current"] as? [String: Any],
                  let daily = json["daily"] as? [String: Any] else { return }
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

struct WeatherDetailView: View {
    @ObservedObject private var weather = WeatherService.shared

    var body: some View {
        if let current = weather.current {
            HStack(spacing: 14) {
                Image(systemName: current.symbol).symbolRenderingMode(.multicolor).font(.system(size: 40))
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.temperatureText).font(.system(size: 30, weight: .semibold))
                    Text("\(weather.cityName) · \(WeatherService.description(for: current.code))")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    Text("↑ \(WeatherService.format(current.high))  ↓ \(WeatherService.format(current.low))")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }
}
