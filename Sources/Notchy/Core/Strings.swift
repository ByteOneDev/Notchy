// Interface strings, French first (default language) then English.
enum Strings {
    static let table: [String: (fr: String, en: String)] = [
        // Menu
        "menu.open": ("Ouvrir le notch", "Open the notch"),
        "menu.settings": ("Réglages…", "Settings…"),
        "menu.updates": ("Rechercher des mises à jour", "Check for Updates"),
        "menu.quit": ("Quitter Notchy", "Quit Notchy"),

        // Common
        "common.add": ("Ajouter", "Add"),
        "common.cancel": ("Annuler", "Cancel"),
        "common.ok": ("OK", "OK"),

        // Media
        "media.nothing": ("Rien en lecture", "Nothing playing"),
        "media.hint": ("Lance Spotify, Musique ou une vidéo YouTube.", "Play something in Spotify, Music or on YouTube."),

        // Live activities
        "battery.charging": ("En charge", "Charging"),
        "battery.unplugged": ("Débranché", "Unplugged"),
        "battery.low": ("Batterie faible", "Low battery"),
        "battery.percent": ("%d %%", "%d%%"),
        "bluetooth.connected": ("Connecté", "Connected"),
        "bluetooth.disconnected": ("Déconnecté", "Disconnected"),
        "meeting.now": ("Maintenant", "Now"),
        "meeting.in": ("Dans %d min", "In %d min"),
        "convert.done": ("Conversion terminée", "Conversion done"),
        "convert.failed": ("Échec de la conversion", "Conversion failed"),
        "convert.unsupported": ("Format non pris en charge", "Unsupported format"),
        "airdrop.sending": ("Envoi via AirDrop", "Sending with AirDrop"),
        "timer.done": ("Minuteur terminé", "Timer done"),

        // Calendar
        "calendar.today": ("Aujourd'hui", "Today"),
        "calendar.allow": ("Autoriser le calendrier", "Allow Calendar Access"),
        "calendar.empty": ("Aucun événement", "No events"),
        "calendar.join": ("Rejoindre", "Join"),
        "calendar.allDay": ("Toute la journée", "All day"),

        // Weather
        "weather.clear": ("Ciel dégagé", "Clear"),
        "weather.partly": ("Partiellement nuageux", "Partly cloudy"),
        "weather.cloudy": ("Nuageux", "Cloudy"),
        "weather.fog": ("Brouillard", "Fog"),
        "weather.drizzle": ("Bruine", "Drizzle"),
        "weather.rain": ("Pluie", "Rain"),
        "weather.snow": ("Neige", "Snow"),
        "weather.storm": ("Orage", "Thunderstorm"),

        // Timers
        "pomodoro.title": ("Pomodoro", "Pomodoro"),
        "pomodoro.focus": ("Concentration", "Focus"),
        "pomodoro.shortBreak": ("Petite pause", "Short break"),
        "pomodoro.longBreak": ("Grande pause", "Long break"),
        "pomodoro.backToWork": ("C'est reparti, au travail !", "Back to work!"),
        "pomodoro.takeBreak": ("Bien joué, fais une pause", "Nice work, take a break"),
        "pomodoro.skip": ("Passer", "Skip"),
        "pomodoro.reset": ("Réinitialiser", "Reset"),
        "timer.title": ("Minuteur", "Timer"),

        // Mirror
        "mirror.allow": ("Autoriser la caméra", "Allow Camera"),
        "mirror.denied": ("Ouvrir les réglages caméra", "Open Camera Settings"),

        // Shelf
        "shelf.empty": ("Dépose des fichiers ici", "Drop files here"),
        "shelf.airdrop": ("AirDrop", "AirDrop"),
        "shelf.convert": ("Convertir", "Convert"),
        "shelf.clear": ("Tout retirer", "Clear All"),
        "shelf.open": ("Ouvrir", "Open"),
        "shelf.reveal": ("Afficher dans le Finder", "Show in Finder"),
        "shelf.remove": ("Retirer de l'étagère", "Remove from Shelf"),

        // Settings panes
        "settings.general": ("Général", "General"),
        "settings.appearance": ("Apparence", "Appearance"),
        "settings.media": ("Musique", "Music"),
        "settings.activities": ("Live activities", "Live Activities"),
        "settings.widgets": ("Widgets", "Widgets"),
        "settings.permissions": ("Autorisations", "Permissions"),
        "settings.about": ("À propos", "About"),

        // General
        "settings.language": ("Langue", "Language"),
        "settings.launchAtLogin": ("Ouvrir au démarrage", "Launch at login"),
        "settings.menuBarIcon": ("Icône dans la barre des menus", "Show menu bar icon"),
        "settings.behavior": ("Comportement", "Behavior"),
        "settings.openOnHover": ("Ouvrir au survol", "Open on hover"),
        "settings.hoverDelay": ("Délai de survol", "Hover delay"),
        "settings.haptics": ("Retour haptique", "Haptic feedback"),
        "settings.swipe": ("Glisser sur le notch pour changer de morceau", "Swipe on the notch to change track"),
        "settings.display": ("Affichage", "Display"),
        "settings.displayTarget": ("Écrans", "Screens"),
        "settings.display.builtIn": ("Écran intégré", "Built-in display"),
        "settings.display.main": ("Écran principal", "Main display"),
        "settings.display.all": ("Tous les écrans", "All displays"),
        "settings.hideFullscreen": ("Masquer en plein écran", "Hide in full screen"),
        "settings.lockScreen": ("Afficher sur l'écran verrouillé", "Show on the lock screen"),

        // Appearance
        "settings.style": ("Style du notch", "Notch style"),
        "settings.style.black": ("Noir", "Black"),
        "settings.style.translucent": ("Semi-transparent", "Translucent"),
        "settings.style.glass": ("Transparent", "Glass"),
        "settings.style.hint": ("Fermé, le notch reste noir pour se fondre avec l'encoche de l'écran.",
                                "When closed, the notch stays black to blend with the screen's cutout."),

        // Media settings
        "settings.media.enabled": ("Afficher la lecture en cours", "Show now playing"),
        "settings.media.visualizer": ("Visualiseur audio", "Audio visualizer"),
        "settings.media.lyrics": ("Paroles synchronisées", "Synced lyrics"),
        "settings.media.apps": ("Applications autorisées", "Allowed apps"),
        "settings.media.apps.hint": ("Seules ces applications apparaissent dans le notch.", "Only these apps show up in the notch."),
        "settings.media.sites": ("Sites autorisés dans les navigateurs", "Allowed sites in browsers"),
        "settings.media.sites.hint": ("Le son d'un navigateur n'est affiché que s'il vient d'un de ces sites. Les autres (archive.org…) sont ignorés.",
                                      "Browser audio only shows when it comes from one of these sites. Others (archive.org…) are ignored."),
        "settings.media.addDomain": ("exemple.com", "example.com"),

        // Activities settings
        "settings.hud": ("HUD", "HUD"),
        "settings.hud.volume": ("Remplacer le HUD du volume", "Replace the volume HUD"),
        "settings.hud.brightness": ("Remplacer le HUD de la luminosité", "Replace the brightness HUD"),
        "settings.hud.needsAccessibility": ("Nécessite l'autorisation Accessibilité.", "Requires the Accessibility permission."),
        "settings.activity.battery": ("Charge et batterie faible", "Charging and low battery"),
        "settings.activity.bluetooth": ("Écouteurs et appareils Bluetooth", "Headphones and Bluetooth devices"),
        "settings.activity.capsLock": ("Verrouillage majuscules", "Caps Lock"),
        "settings.activity.privacy": ("Caméra et micro utilisés", "Camera and microphone in use"),
        "settings.activity.meeting": ("Réunion imminente", "Upcoming meeting"),

        // Widgets settings
        "settings.widgets.calendar": ("Calendrier", "Calendar"),
        "settings.widgets.calendar.enabled": ("Afficher le calendrier", "Show the calendar"),
        "settings.widgets.weather": ("Météo", "Weather"),
        "settings.widgets.weather.enabled": ("Afficher la météo", "Show the weather"),
        "settings.widgets.weather.location": ("Utiliser ma position", "Use my location"),
        "settings.widgets.weather.city": ("Ville", "City"),
        "settings.widgets.weather.notFound": ("Ville introuvable", "City not found"),
        "settings.widgets.weather.unit": ("Unité", "Unit"),
        "settings.pomodoro.work": ("Concentration : %d min", "Focus: %d min"),
        "settings.pomodoro.short": ("Petite pause : %d min", "Short break: %d min"),
        "settings.pomodoro.long": ("Grande pause : %d min", "Long break: %d min"),
        "settings.pomodoro.rounds": ("Sessions avant la grande pause : %d", "Sessions before long break: %d"),
        "settings.widgets.other": ("Autres", "Other"),
        "settings.widgets.shelf": ("Étagère, AirDrop et conversion", "Shelf, AirDrop and conversion"),
        "settings.widgets.mirror": ("Miroir", "Mirror"),

        // Permissions
        "perm.accessibility": ("Accessibilité", "Accessibility"),
        "perm.accessibility.why": ("HUD du volume et de la luminosité, verrouillage majuscules", "Volume and brightness HUD, Caps Lock"),
        "perm.calendar": ("Calendrier", "Calendar"),
        "perm.calendar.why": ("Afficher tes événements", "Show your events"),
        "perm.camera": ("Caméra", "Camera"),
        "perm.camera.why": ("Fonction Miroir", "Mirror feature"),
        "perm.location": ("Localisation", "Location"),
        "perm.location.why": ("Météo locale", "Local weather"),
        "perm.automation": ("Automatisation", "Automation"),
        "perm.automation.why": ("Lire Spotify, Musique et les onglets du navigateur (demandé à la première lecture)",
                                "Read Spotify, Music and browser tabs (asked on first playback)"),
        "perm.grant": ("Autoriser", "Allow"),
        "perm.open": ("Ouvrir", "Open"),
        "perm.granted": ("Autorisé", "Allowed"),
        "perm.footer": ("Toutes les données restent sur ton Mac.", "All data stays on your Mac."),

        // About & updates
        "about.version": ("Version %@", "Version %@"),
        "about.download": ("Télécharger", "Download"),
        "update.checking": ("Recherche…", "Checking…"),
        "update.failed": ("Impossible de vérifier les mises à jour", "Couldn't check for updates"),
        "update.available": ("Version %@ disponible", "Version %@ available"),
        "update.upToDate": ("Notchy est à jour", "Notchy is up to date"),
    ]
}
