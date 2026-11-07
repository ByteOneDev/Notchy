import SwiftUI

/// Ready-made lists of sites to block by category, in the spirit of Jomo's, and the sites
/// the blocked-sites field completes as you type.
enum SiteCatalog {
    struct Category: Identifiable {
        let id: String
        let icon: String
        let color: Color
        let domains: [String]
        var title: String { L("sites.category.\(id)") }
    }

    static let categories: [Category] = [
        Category(id: "social", icon: "person.2.fill", color: .blue, domains: [
            "facebook.com", "instagram.com", "x.com", "twitter.com", "tiktok.com", "snapchat.com", "reddit.com",
            "linkedin.com", "pinterest.com", "tumblr.com", "threads.net", "threads.com", "bsky.app", "mastodon.social",
            "bereal.com", "quora.com", "vk.com", "9gag.com", "lemon8-app.com",
        ]),
        Category(id: "video", icon: "play.rectangle.fill", color: .red, domains: [
            "youtube.com", "twitch.tv", "kick.com", "netflix.com", "primevideo.com", "disneyplus.com", "canalplus.com",
            "crunchyroll.com", "animationdigitalnetwork.com", "dailymotion.com", "vimeo.com", "max.com", "hbomax.com",
            "paramountplus.com", "tv.apple.com", "molotov.tv", "france.tv", "tf1.fr", "m6plus.fr", "arte.tv",
            "hulu.com", "plex.tv", "pluto.tv", "rakuten.tv",
        ]),
        Category(id: "news", icon: "newspaper.fill", color: .gray, domains: [
            "lemonde.fr", "lefigaro.fr", "liberation.fr", "20minutes.fr", "bfmtv.com", "francetvinfo.fr", "franceinfo.fr",
            "leparisien.fr", "ouest-france.fr", "huffingtonpost.fr", "mediapart.fr", "cnews.fr", "lexpress.fr", "lepoint.fr",
            "nouvelobs.com", "rfi.fr", "tf1info.fr", "actu.fr", "courrierinternational.com", "nytimes.com", "theguardian.com",
            "bbc.com", "bbc.co.uk", "cnn.com", "washingtonpost.com", "foxnews.com", "reuters.com", "news.google.com",
            "news.ycombinator.com", "apnews.com", "bloomberg.com",
        ]),
        Category(id: "sports", icon: "sportscourt.fill", color: .green, domains: [
            "lequipe.fr", "rmcsport.bfmtv.com", "eurosport.fr", "eurosport.com", "footmercato.net", "sofoot.com", "goal.com",
            "beinsports.com", "espn.com", "skysports.com", "onefootball.com", "flashscore.fr", "flashscore.com", "sports.fr",
        ]),
        Category(id: "shopping", icon: "cart.fill", color: .orange, domains: [
            "amazon.fr", "amazon.com", "ebay.fr", "ebay.com", "aliexpress.com", "temu.com", "shein.com", "vinted.fr",
            "leboncoin.fr", "cdiscount.com", "fnac.com", "zalando.fr", "etsy.com", "wish.com", "rakuten.fr", "darty.com",
            "boulanger.com", "asos.com", "veepee.fr", "ldlc.com", "backmarket.fr", "ikea.com", "decathlon.fr",
        ]),
        Category(id: "games", icon: "gamecontroller.fill", color: .purple, domains: [
            "store.steampowered.com", "steamcommunity.com", "epicgames.com", "roblox.com", "chess.com", "lichess.org",
            "poki.com", "crazygames.com", "miniclip.com", "itch.io", "coolmathgames.com", "minecraft.net", "battle.net",
            "riotgames.com", "leagueoflegends.com", "jeuxvideo.com", "ign.com", "gamekult.com", "geoguessr.com",
        ]),
        Category(id: "gambling", icon: "dice.fill", color: .yellow, domains: [
            "betclic.fr", "winamax.fr", "unibet.fr", "fdj.fr", "pmu.fr", "zebet.fr", "pokerstars.fr", "bwin.fr", "netbet.fr",
            "bet365.com", "stake.com", "draftkings.com", "fanduel.com", "pokerstars.com", "888poker.com",
        ]),
        Category(id: "dating", icon: "heart.fill", color: .pink, domains: [
            "tinder.com", "bumble.com", "hinge.co", "meetic.fr", "happn.com", "badoo.com", "okcupid.com", "fruitz.io",
            "match.com", "grindr.com", "adopteunmec.com", "once.com", "lovoo.com",
        ]),
        Category(id: "messaging", icon: "bubble.left.and.bubble.right.fill", color: .teal, domains: [
            "discord.com", "web.whatsapp.com", "messenger.com", "web.telegram.org", "slack.com", "teams.microsoft.com",
        ]),
        Category(id: "adult", icon: "eye.slash.fill", color: .red, domains: [
            "pornhub.com", "xvideos.com", "xnxx.com", "xhamster.com", "redtube.com", "youporn.com", "onlyfans.com",
            "chaturbate.com", "stripchat.com", "spankbang.com", "eporner.com", "brazzers.com", "fansly.com", "tnaflix.com",
        ]),
    ]

    static func category(_ id: String) -> Category? { categories.first { $0.id == id } }

    /// Names people type that don't look like the site's address.
    private static let aliases: [String: [String]] = [
        "twitter": ["x.com", "twitter.com"], "insta": ["instagram.com"], "fb": ["facebook.com"],
        "prime": ["primevideo.com"], "disney": ["disneyplus.com"], "canal": ["canalplus.com"], "adn": ["animationdigitalnetwork.com"],
        "steam": ["store.steampowered.com", "steamcommunity.com"], "whatsapp": ["web.whatsapp.com"], "telegram": ["web.telegram.org"],
        "france tv": ["france.tv"], "hacker news": ["news.ycombinator.com"], "le monde": ["lemonde.fr"], "l'equipe": ["lequipe.fr"],
    ]

    /// Other well-known sites the field can complete.
    private static let extras = [
        "wikipedia.org", "github.com", "stackoverflow.com", "chatgpt.com", "claude.ai", "gemini.google.com", "notion.so",
        "spotify.com", "deezer.com", "soundcloud.com", "medium.com", "substack.com", "mail.google.com", "outlook.com",
        "google.com", "imdb.com", "allocine.fr", "senscritique.com", "letterboxd.com", "goodreads.com", "booking.com",
        "airbnb.com", "tripadvisor.fr", "marmiton.org", "doctolib.fr", "deepl.com", "canva.com", "figma.com", "producthunt.com",
        "dribbble.com", "behance.net", "anime-sama.fr", "webtoons.com", "mangadex.org",
    ]

    private static let known: [String] = {
        var seen = Set<String>()
        return (categories.flatMap(\.domains) + extras).filter { seen.insert($0).inserted }
    }()

    /// Sites matching what is being typed: "you" → youtube.com first, then other matches.
    static func suggestions(for text: String, excluding: [String] = []) -> [String] {
        let query = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard query.count >= 2 else { return [] }
        var result: [String] = []
        func add(_ site: String) { if !result.contains(site), !excluding.contains(site) { result.append(site) } }
        for (name, sites) in aliases where name.hasPrefix(query) { sites.forEach(add) }
        // In catalog order: the best-known sites come first in each list.
        known.filter { $0.hasPrefix(query) }.forEach(add)
        // Then any part of the address: "tube" → youtube.com, "steam" → store.steampowered.com.
        known.filter { site in site.split(separator: ".").contains { $0.hasPrefix(query) } || site.contains(query) }.forEach(add)
        return Array(result.prefix(6))
    }
}
