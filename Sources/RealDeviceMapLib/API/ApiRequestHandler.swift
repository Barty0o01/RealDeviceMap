//
//  ApiRequestHandler.swift
//  RealDeviceMapLib
//
//  Created by Florian Kostenzer on 18.09.18.
//
//  swiftlint:disable superfluous_disable_command file_length type_body_length

import Foundation
import PerfectLib
import PerfectHTTP
import PerfectMustache
import PerfectSessionMySQL
import POGOProtos
import S2Geometry
import PerfectThread

public class ApiRequestHandler {

    private static var sessionDriver = MySQLSessions()

    public static func handle(request: HTTPRequest, response: HTTPResponse, route: WebServer.APIPage) {

        switch route {
        case .getData:
            handleGetData(request: request, response: response)
        case .setData:
            handleSetData(request: request, response: response)
        }
    }

    public static var start: Date = Date(timeIntervalSince1970: 0)

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private static func getPerms(request: HTTPRequest, response: HTTPResponse, route: WebServer.APIPage)
	-> [Group.Perm]? {
        let tmp = WebRequestHandler.getPerms(request: request, fromCache: true)
        let perms = tmp.perms
        let username = tmp.username

        if username == nil || username == "", let authorization = request.header(.authorization) {
            let base64String = authorization.replacingOccurrences(of: "Basic ", with: "")
            if let data = Data(base64Encoded: base64String), let string = String(data: data, encoding: .utf8) {
                let split = string.components(separatedBy: ":")
                if split.count == 2 {
                    if let usernameEmail = split[0].stringByDecodingURL, let password = split[1].stringByDecodingURL {
                        let user: User
                        do {
                            let host = request.host
                            if usernameEmail.contains("@") {
                                user = try User.login(email: usernameEmail, password: password, host: host)
                            } else {
                                user = try User.login(username: usernameEmail, password: password, host: host)
                            }
                        } catch {
                            if error is DBController.DBError {
                                response.respondWithError(status: .internalServerError)
                                return nil
                            } else if let error = error as? User.LoginError {
                                switch error.type {
                                case .limited, .usernamePasswordInvalid:
                                    response.respondWithError(status: .unauthorized)
                                    return nil
                                case .undefined:
                                    response.respondWithError(status: .internalServerError)
                                    return nil
                                }
                            } else {
                                response.respondWithError(status: .internalServerError)
                                return nil
                            }
                        }

                        request.session?.userid = user.username
                        if user.group != nil {
                            request.session?.data["perms"] = Group.Perm.permsToNumber(perms: user.group!.perms)
                        }
                        sessionDriver.save(session: request.session!)
                        switch route {
                        case .getData:
                            handleGetData(request: request, response: response)
                        case .setData:
                            handleSetData(request: request, response: response)
                        }
                        return nil
                    }
                }

            }
        }
        return perms
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private static func handleGetData(request: HTTPRequest, response: HTTPResponse) {
        guard let perms = getPerms(request: request, response: response, route: WebServer.APIPage.getData) else {
            return
        }
        let minLat = request.param(name: "min_lat")?.toDouble()
        let maxLat = request.param(name: "max_lat")?.toDouble()
        let minLon = request.param(name: "min_lon")?.toDouble()
        let maxLon = request.param(name: "max_lon")?.toDouble()
        let instance = request.param(name: "instance")
        let iconStyle = request.param(name: "icon_style") ?? "Default"
        let showGyms = request.param(name: "show_gyms")?.toBool() ?? false
        let showRaids = request.param(name: "show_raids")?.toBool() ?? false
        let showPokestops = request.param(name: "show_pokestops")?.toBool() ?? false
        let showInvasions = request.param(name: "show_invasions")?.toBool() ?? false
        let showQuests = request.param(name: "show_quests")?.toBool() ?? false
        let questFilterExclude = request.param(name: "quest_filter_exclude")?.jsonDecodeForceTry() as? [String]
        let showPokemon = request.param(name: "show_pokemon")?.toBool() ?? false
        let pokemonFilterEventOnly = request.param(name: "pokemon_filter_event_only")?.toBool() ?? false
        let pokemonFilterExclude = request.param(name: "pokemon_filter_exclude")?.jsonDecodeForceTry() as? [Int]
        let pokemonFilterIV = request.param(name: "pokemon_filter_iv")?.jsonDecodeForceTry() as? [String: String]
        let excludeCellPokemon = request.param(name: "pokemon_exclude_cell")?.toBool() ?? false
        let raidFilterExclude = request.param(name: "raid_filter_exclude")?.jsonDecodeForceTry() as? [String]
        let gymFilterExclude = request.param(name: "gym_filter_exclude")?.jsonDecodeForceTry() as? [String]
        let pokestopFilterExclude = request.param(name: "pokestop_filter_exclude")?.jsonDecodeForceTry() as? [String]
        let invasionFilterExclude = request.param(name: "invasion_filter_exclude")?.jsonDecodeForceTry() as? [Int]
        let spawnpointFilterExclude = request.param(name: "spawnpoint_filter_exclude")?
            .jsonDecodeForceTry() as? [String]
        let pokestopShowOnlyAr = request.param(name: "pokestop_show_only_ar")?.toBool() ?? false
        let pokestopShowOnlySponsored = request.param(name: "pokestop_show_only_sponsored")?.toBool() ?? false
        let questShowOnlyAr = request.param(name: "quest_show_only_ar")?.toBool() ?? false
        let gymShowOnlyAr = request.param(name: "gym_show_only_ar")?.toBool() ?? false
        let gymShowOnlySponsored = request.param(name: "gym_show_only_sponsored")?.toBool() ?? false
        let showSpawnpoints = request.param(name: "show_spawnpoints")?.toBool() ?? false
        let showCells = request.param(name: "show_cells")?.toBool() ?? false
        let showSubmissionPlacementCells = request.param(name: "show_submission_placement_cells")?.toBool() ?? false
        let showSubmissionTypeCells = request.param(name: "show_submission_type_cells")?.toBool() ?? false
        let showWeathers = request.param(name: "show_weathers")?.toBool() ?? false
        let showDevices = request.param(name: "show_devices")?.toBool() ?? false
        let showActiveDevices = request.param(name: "show_active_devices")?.toBool() ?? false
        let showInstances = request.param(name: "show_instances")?.toBool() ?? false
        let skipInstanceStatus = request.param(name: "skip_instance_status")?.toBool() ?? false
        let showDeviceGroups = request.param(name: "show_devicegroups")?.toBool() ?? false
        let showUsers = request.param(name: "show_users")?.toBool() ?? false
        let showGroups = request.param(name: "show_groups")?.toBool() ?? false
        let showPokemonFilter = request.param(name: "show_pokemon_filter")?.toBool() ?? false
        let showQuestFilter = request.param(name: "show_quest_filter")?.toBool() ?? false
        let showRaidFilter = request.param(name: "show_raid_filter")?.toBool() ?? false
        let showGymFilter = request.param(name: "show_gym_filter")?.toBool() ?? false
        let showPokestopFilter = request.param(name: "show_pokestop_filter")?.toBool() ?? false
        let showInvasionFilter = request.param(name: "show_invasion_filter")?.toBool() ?? false
        let showSpawnpointFilter = request.param(name: "show_spawnpoint_filter")?.toBool() ?? false
        let formatted = request.param(name: "formatted")?.toBool() ?? false
        let lastUpdate = request.param(name: "last_update")?.toUInt32() ?? 0
        let showAssignments = request.param(name: "show_assignments")?.toBool() ?? false
        let showAssignmentGroups = request.param(name: "show_assignmentgroups")?.toBool() ?? false
        let showWebhooks = request.param(name: "show_webhooks")?.toBool() ?? false
        let showIVQueue = request.param(name: "show_ivqueue")?.toBool() ?? false
        let showDiscordRules = request.param(name: "show_discordrules")?.toBool() ?? false
        let showStatus = request.param(name: "show_status")?.toBool() ?? false
        let showDashboardStats = request.param(name: "show_dashboard_stats")?.toBool() ?? false
        let showPokemonStats = request.param(name: "show_pokemon_stats")?.toBool() ?? false
        let showRaidStats = request.param(name: "show_raid_stats")?.toBool() ?? false
        let showQuestStats = request.param(name: "show_quest_stats")?.toBool() ?? false
        let showInvasionStats = request.param(name: "show_invasion_stats")?.toBool() ?? false
        let showTop10Stats = request.param(name: "show_top10_stats")?.toBool() ?? false
        let date = request.param(name: "date") ?? ""
        let showCommdayStats = request.param(name: "show_commday_stats")?.toBool() ?? false
        let pokemonId = request.param(name: "pokemon_id")?.toUInt16() ?? 0
        let startTimestamp = request.param(name: "start_timestamp") ?? ""
        let endTimestamp = request.param(name: "end_timestamp") ?? ""
        let scanNext = request.param(name: "scan_next")?.toBool() ?? false
        let queueSize = request.param(name: "queue_size")?.toBool() ?? false

        if (showGyms || showRaids || showPokestops || showPokemon || showSpawnpoints ||
            showCells || showSubmissionTypeCells || showSubmissionPlacementCells || showWeathers) &&
            (minLat == nil || maxLat == nil || minLon == nil || maxLon == nil) {
            response.respondWithError(status: .badRequest)
            return
        }

        let permViewMap = perms.contains(.viewMap)

        guard let mysql = DBController.global.mysql else {
            response.respondWithError(status: .internalServerError)
            return
        }

        var data = [String: Any]()
        let isPost = request.method == .post
        let permShowRaid = perms.contains(.viewMapRaid)
        let permShowGym = perms.contains(.viewMapGym)
        if isPost && (permViewMap && (showGyms && permShowGym || showRaids && permShowRaid)) {
            data["gyms"] = try? Gym.getAll(
                mysql: mysql, minLat: minLat!, maxLat: maxLat!, minLon: minLon!, maxLon: maxLon!, updated: lastUpdate,
                raidsOnly: !showGyms, showRaids: permShowRaid, raidFilterExclude: raidFilterExclude,
                gymFilterExclude: gymFilterExclude, gymShowOnlyAr: gymShowOnlyAr,
                gymShowOnlySponsored: gymShowOnlySponsored
            )
        }
        let permShowStops = perms.contains(.viewMapPokestop)
        let permShowQuests = perms.contains(.viewMapQuest)
        let permShowLures = perms.contains(.viewMapLure)
        let permShowInvasions = perms.contains(.viewMapInvasion)
        if isPost && (permViewMap && (
                (showPokestops && permShowStops) ||
                (showQuests && permShowQuests) ||
                (showInvasions && permShowInvasions)
        )) {
            data["pokestops"] = try? Pokestop.getAll(
                mysql: mysql, minLat: minLat!, maxLat: maxLat!, minLon: minLon!, maxLon: maxLon!, updated: lastUpdate,
                showPokestops: showPokestops, showQuests: showQuests && permShowQuests, showLures: permShowLures,
                showInvasions: showInvasions && permShowInvasions, questFilterExclude: questFilterExclude,
                pokestopFilterExclude: pokestopFilterExclude, pokestopShowOnlyAr: pokestopShowOnlyAr,
                pokestopShowOnlySponsored: pokestopShowOnlySponsored,
                invasionFilterExclude: invasionFilterExclude, showAlternativeQuests: questShowOnlyAr
            )
        }
        let permShowPokemon = perms.contains(.viewMapPokemon)
        let permShowIV = perms.contains(.viewMapIV)
        let permShowEventPokemon = perms.contains(.viewMapEventPokemon)
        if isPost && permViewMap && showPokemon && permShowPokemon {
            data["pokemon"] = try? Pokemon.getAll(
                mysql: mysql, minLat: minLat!, maxLat: maxLat!, minLon: minLon!, maxLon: maxLon!,
                showIV: permShowIV, updated: lastUpdate, pokemonFilterExclude: pokemonFilterExclude,
                pokemonFilterIV: pokemonFilterIV, isEvent: pokemonFilterEventOnly && permShowEventPokemon,
                excludeCellPokemon: excludeCellPokemon
            )
        }
        if isPost && permViewMap && showSpawnpoints && perms.contains(.viewMapSpawnpoint) {
            data["spawnpoints"] = try? SpawnPoint.getAll(
                mysql: mysql, minLat: minLat!, maxLat: maxLat!, minLon: minLon!, maxLon: maxLon!,
                updated: lastUpdate, spawnpointFilterExclude: spawnpointFilterExclude
            )
        }
        if isPost && permViewMap && showActiveDevices && perms.contains(.viewMapDevice) {
            data["active_devices"] = try? Device.getAll(
                mysql: mysql
            )
        }
        if isPost && showCells && perms.contains(.viewMapCell) {
            data["cells"] = try? Cell.getAll(
                mysql: mysql, minLat: minLat!, maxLat: maxLat!, minLon: minLon!, maxLon: maxLon!, updated: lastUpdate
            )
        }
        if lastUpdate == 0 && isPost && showSubmissionPlacementCells && perms.contains(.viewMapSubmissionCells) {
            let result = try? SubmissionPlacementCell.getAll(
                mysql: mysql, minLat: minLat!, maxLat: maxLat!, minLon: minLon!, maxLon: maxLon!
            )
            data["submission_placement_cells"] = result?.cells
            data["submission_placement_rings"] = result?.rings
        }
        if lastUpdate == 0 && isPost && showSubmissionTypeCells && perms.contains(.viewMapSubmissionCells) {
            data["submission_type_cells"] = try? SubmissionTypeCell.getAll(
                mysql: mysql, minLat: minLat!, maxLat: maxLat!, minLon: minLon!, maxLon: maxLon!
            )
        }
        if isPost && showWeathers && perms.contains(.viewMapWeather) {
			data["weather"] = try? Weather.getAll(
                mysql: mysql, minLat: minLat!, maxLat: maxLat!, minLon: minLon!, maxLon: maxLon!, updated: lastUpdate
            )
        }
        if permViewMap && showPokemonFilter {

            let hideString = Localizer.global.get(value: "filter_hide")
            let showString = Localizer.global.get(value: "filter_show")
            let onString = Localizer.global.get(value: "filter_on")
            let offString = Localizer.global.get(value: "filter_off")
            let ivString = Localizer.global.get(value: "filter_iv")

            let smallString = Localizer.global.get(value: "filter_small")
            let normalString = Localizer.global.get(value: "filter_normal")
            let largeString = Localizer.global.get(value: "filter_large")
            let hugeString = Localizer.global.get(value: "filter_huge")

            let miscString = Localizer.global.get(value: "filter_misc")
            let pokemonTypeString = Localizer.global.get(value: "filter_pokemon")
            let globalIVTypeString = Localizer.global.get(value: "filter_global_iv")

            let eventOnlyString = Localizer.global.get(value: "filter_event_only")
            let includeCellString = Localizer.global.get(value: "filter_include_cell")
            let globalIV = Localizer.global.get(value: "filter_global_iv")
            let configureString = Localizer.global.get(value: "filter_configure")
            let andString = Localizer.global.get(value: "filter_and")
            let orString = Localizer.global.get(value: "filter_or")

            var pokemonData = [[String: Any]]()

            if permShowEventPokemon {
                 let filter = """
                    <div class="btn-group btn-group-toggle" data-toggle="buttons">
                        <label class="btn btn-sm btn-off select-button-new" data-id="event_only"
                         data-type="pokemon-iv" data-info="event_only_hide">
                            <input type="radio" name="options" id="hide" autocomplete="off">\(offString)
                        </label>
                        <label class="btn btn-sm btn-on select-button-new" data-id="event_only"
                         data-type="pokemon-iv" data-info="event_only_show">
                            <input type="radio" name="options" id="show" autocomplete="off">\(onString)
                        </label>
                    </div>
                """
                pokemonData.append([
                    "id": [
                        "formatted": "",
                        "sort": -2
                    ],
                    "name": eventOnlyString,
                    "image": "Event",
                    "filter": filter,
                    "size": "",
                    "type": miscString
                ])
            }
            if Pokemon.cellPokemonEnabled {
                let filter = """
                    <div class="btn-group btn-group-toggle" data-toggle="buttons">
                        <label class="btn btn-sm btn-off select-button-new" data-id="show_cell"
                         data-type="pokemon-iv" data-info="show_cell_hide">
                            <input type="radio" name="options" id="hide" autocomplete="off">\(offString)
                        </label>
                        <label class="btn btn-sm btn-on select-button-new" data-id="show_cell"
                         data-type="pokemon-iv" data-info="show_cell_show">
                            <input type="radio" name="options" id="show" autocomplete="off">\(onString)
                        </label>
                    </div>
                """
                pokemonData.append([
                    "id": [
                        "formatted": "",
                        "sort": -1
                    ],
                    "name": includeCellString,
                    "image": "<img class=\"lazy_load\" data-src=\"/image-api/misc?style=\(iconStyle)&id=grass\" " +
                            "style=\"height:50px; width:50px;\">",
                    "filter": filter,
                    "size": "",
                    "type": miscString
                ])
            }

            if permShowIV {
                for i in 0...1 {

                    let id: String
                    if i == 0 {
                        id = "and"
                    } else {
                        id = "or"
                    }

                     let filter = """
                        <div class="btn-group btn-group-toggle" data-toggle="buttons">
                            <label class="btn btn-sm btn-off select-button-new" data-id="\(id)"
                             data-type="pokemon-iv" data-info="off">
                                <input type="radio" name="options" id="hide" autocomplete="off">\(offString)
                            </label>
                            <label class="btn btn-sm btn-on select-button-new" data-id="\(id)"
                             data-type="pokemon-iv" data-info="on">
                                <input type="radio" name="options" id="show" autocomplete="off">\(onString)
                            </label>
                        </div>
                    """

                    let andOrString: String
                    if i == 0 {
                        andOrString = andString
                    } else {
                        andOrString = orString
                    }

                    let size = "<button class=\"btn btn-sm btn-primary configure-button-new\" " +
                        "data-id=\"\(id)\" data-type=\"pokemon-iv\" data-info=\"global-iv\">\(configureString)</button>"

                    pokemonData.append([
                        "id": [
                            "formatted": andOrString,
                            "sort": i
                        ],
                        "name": globalIV,
                        "image": andOrString,
                        "filter": filter,
                        "size": size,
                        "type": globalIVTypeString
                    ])

                }
            }

            for i in 1...WebRequestHandler.maxPokemonId {

                let ivLabel: String
                if permShowIV {
                    ivLabel = """
                        <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                         data-type="pokemon" data-info="iv">
                        <input type="radio" name="options" id="iv" autocomplete="off">\(ivString)
                        </label>
                    """
                } else {
                    ivLabel = ""
                }
                let filter = """
                    <div class="btn-group btn-group-toggle" data-toggle="buttons">
                        <label class="btn btn-sm btn-off select-button-new" data-id="\(i)"
                         data-type="pokemon" data-info="hide">
                            <input type="radio" name="options" id="hide" autocomplete="off">\(hideString)
                        </label>
                        <label class="btn btn-sm btn-on select-button-new" data-id="\(i)"
                         data-type="pokemon" data-info="show">
                            <input type="radio" name="options" id="show" autocomplete="off">\(showString)
                        </label>
                        \(ivLabel)
                    </div>
                """

                let size = """
                    <div class="btn-group btn-group-toggle" data-toggle="buttons">
                        <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                         data-type="pokemon" data-info="small">
                            <input type="radio" name="options" id="hide" autocomplete="off">\(smallString)
                        </label>
                        <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                         data-type="pokemon" data-info="normal">
                            <input type="radio" name="options" id="show" autocomplete="off">\(normalString)
                        </label>
                        <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                         data-type="pokemon" data-info="large">
                            <input type="radio" name="options" id="show" autocomplete="off">\(largeString)
                        </label>
                        <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                         data-type="pokemon" data-info="huge">
                            <input type="radio" name="options" id="show" autocomplete="off">\(hugeString)
                        </label>
                    </div>
                """

                pokemonData.append([
                    "id": [
                        "formatted": String(format: "%03d", i),
                        "sort": i+1
                    ],
                    "name": Localizer.global.get(value: "poke_\(i)") ,
                    "image": "<img class=\"lazy_load\" data-src=\"/image-api/pokemon?style=\(iconStyle)&id=\(i)\" " +
                             "style=\"height:50px; width:50px;\">",
                    "filter": filter,
                    "size": size,
                    "type": pokemonTypeString
                ])
            }
            data["pokemon_filters"] = pokemonData
        }

        if permViewMap && showQuestFilter {

            let hideString = Localizer.global.get(value: "filter_hide")
            let showString = Localizer.global.get(value: "filter_show")

            let smallString = Localizer.global.get(value: "filter_small")
            let normalString = Localizer.global.get(value: "filter_normal")
            let largeString = Localizer.global.get(value: "filter_large")
            let hugeString = Localizer.global.get(value: "filter_huge")

            let pokemonTypeString = Localizer.global.get(value: "filter_pokemon")
            let miscTypeString = Localizer.global.get(value: "filter_misc")
            let itemsTypeString = Localizer.global.get(value: "filter_items")
            let generalString = Localizer.global.get(value: "filter_general")

            let showArQuestsString = Localizer.global.get(value: "filter_quest_show_ar")

            var questData = [[String: Any]]()

            let filter =
                """
                <div class="btn-group btn-group-toggle" data-toggle="buttons">
                    <label class="btn btn-sm btn-off select-button-new" data-id="ar"
                        data-type="quest-ar" data-info="hide">
                        <input type="radio" name="options" id="hide" autocomplete="off">\(hideString)
                    </label>
                    <label class="btn btn-sm btn-on select-button-new" data-id="ar"
                        data-type="quest-ar" data-info="show">
                        <input type="radio" name="options" id="show" autocomplete="off">\(showString)
                    </label>
                </div>
                """
            questData.append([
                "id": [
                    "formatted": "",
                    "sort": -1
                ],
                "name": showArQuestsString,
                "image": "<img class=\"lazy_load\" data-src=\"/image-api/misc?style=\(iconStyle)&id=ar\" " +
                        "style=\"height:50px; width:50px;\">",
                "filter": filter,
                "size": "",
                "type": generalString
            ])

            // reward types:
            for rewardType in QuestRewardProto.TypeEnum.allAvailable {
                let rewardTypeName = Localizer.global.get(value: "quest_reward_\(rewardType.rawValue)")
                if rewardType == .pokemonEncounter {
                    for i in 1...WebRequestHandler.maxPokemonId {
                        let filter =
                            """
                            <div class="btn-group btn-group-toggle" data-toggle="buttons">
                                <label class="btn btn-sm btn-off select-button-new" data-id="\(i)"
                                    data-type="quest-pokemon" data-info="hide">
                                    <input type="radio" name="options" id="hide" autocomplete="off">\(hideString)
                                </label>
                                <label class="btn btn-sm btn-on select-button-new" data-id="\(i)"
                                    data-type="quest-pokemon" data-info="show">
                                    <input type="radio" name="options" id="show" autocomplete="off">\(showString)
                                </label>
                            </div>
                            """
                        let size =
                            """
                            <div class="btn-group btn-group-toggle" data-toggle="buttons">
                                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                                    data-type="quest-pokemon" data-info="small">
                                    <input type="radio" name="options" id="hide" autocomplete="off">\(smallString)
                                </label>
                                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                                    data-type="quest-pokemon" data-info="normal">
                                    <input type="radio" name="options" id="show" autocomplete="off">\(normalString)
                                </label>
                                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                                    data-type="quest-pokemon" data-info="large">
                                    <input type="radio" name="options" id="show" autocomplete="off">\(largeString)
                                </label>
                                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                                    data-type="quest-pokemon" data-info="huge">
                                    <input type="radio" name="options" id="show" autocomplete="off">\(hugeString)
                                </label>
                            </div>
                            """

                        questData.append([
                            "id": [
                                "formatted": String(format: "%03d", i),
                                "sort": 200+i
                            ],
                            "name": Localizer.global.get(value: "poke_\(i)") ,
                            "image": "<img class=\"lazy_load\" data-src=\"/image-api/pokemon?style=\(iconStyle)" +
                                "&id=\(i)\" style=\"height:50px; width:50px;\">",
                            "filter": filter,
                            "size": size,
                            "type": pokemonTypeString
                        ])
                    }
                } else if rewardType == .item {
                    // Items
                    var itemI = 1
                    for item in Item.allAvailable {
                        let filter =
                            """
                            <div class="btn-group btn-group-toggle" data-toggle="buttons">
                                <label class="btn btn-sm btn-off select-button-new" data-id="\(item.rawValue)"
                                    data-type="quest-item" data-info="hide">
                                    <input type="radio" name="options" id="hide" autocomplete="off">\(hideString)
                                </label>
                                <label class="btn btn-sm btn-on select-button-new" data-id="\(item.rawValue)"
                                    data-type="quest-item" data-info="show">
                                    <input type="radio" name="options" id="show" autocomplete="off">\(showString)
                                </label>
                            </div>
                            """
                        let size =
                            """
                            <div class="btn-group btn-group-toggle" data-toggle="buttons">
                                <label class="btn btn-sm btn-size select-button-new" data-id="\(item.rawValue)"
                                    data-type="quest-item" data-info="small">
                                    <input type="radio" name="options" id="hide" autocomplete="off">\(smallString)
                                </label>
                                <label class="btn btn-sm btn-size select-button-new" data-id="\(item.rawValue)"
                                    data-type="quest-item" data-info="normal">
                                    <input type="radio" name="options" id="show" autocomplete="off">\(normalString)
                                </label>
                                <label class="btn btn-sm btn-size select-button-new" data-id="\(item.rawValue)"
                                    data-type="quest-item" data-info="large">
                                    <input type="radio" name="options" id="show" autocomplete="off">\(largeString)
                                </label>
                                <label class="btn btn-sm btn-size select-button-new" data-id="\(item.rawValue)"
                                    data-type="quest-item" data-info="huge">
                                    <input type="radio" name="options" id="show" autocomplete="off">\(hugeString)
                                </label>
                            </div>
                            """

                        questData.append([
                            "id": [
                                "formatted": String(format: "%03d", itemI),
                                "sort": 100+itemI
                            ],
                            "name": Localizer.global.get(value: "item_\(item.rawValue)") ,
                            "image": "<img class=\"lazy_load\" " +
                                "data-src=\"/image-api/reward?style=\(iconStyle)&" +
                                "id=\(item.rawValue)&type=\(rewardType.rawValue)\" " +
                                "style=\"height:50px; width:50px;\">",
                            "filter": filter,
                            "size": size,
                            "type": itemsTypeString
                        ])
                        itemI += 1
                    }
                } else {
                    // Misc
                    let filter =
                        """
                        <div class="btn-group btn-group-toggle" data-toggle="buttons">
                            <label class="btn btn-sm btn-off select-button-new" data-id="\(rewardType.rawValue)"
                                  data-type="quest-misc" data-info="hide">
                                  <input type="radio" name="options" id="hide" autocomplete="off">\(hideString)
                            </label>
                            <label class="btn btn-sm btn-on select-button-new" data-id="\(rewardType.rawValue)"
                                  data-type="quest-misc" data-info="show">
                                  <input type="radio" name="options" id="show" autocomplete="off">\(showString)
                            </label>
                        </div>
                        """
                    let size =
                        """
                        <div class="btn-group btn-group-toggle" data-toggle="buttons">
                            <label class="btn btn-sm btn-size select-button-new" data-id="\(rewardType.rawValue)"
                                data-type="quest-misc" data-info="small">
                                <input type="radio" name="options" id="hide" autocomplete="off">\(smallString)
                            </label>
                            <label class="btn btn-sm btn-size select-button-new" data-id="\(rewardType.rawValue)"
                                data-type="quest-misc" data-info="normal">
                                <input type="radio" name="options" id="show" autocomplete="off">\(normalString)
                            </label>
                            <label class="btn btn-sm btn-size select-button-new" data-id="\(rewardType.rawValue)"
                                data-type="quest-misc" data-info="large">
                                <input type="radio" name="options" id="show" autocomplete="off">\(largeString)
                            </label>
                            <label class="btn btn-sm btn-size select-button-new" data-id="\(rewardType.rawValue)"
                                data-type="quest-misc" data-info="huge">
                                <input type="radio" name="options" id="show" autocomplete="off">\(hugeString)
                            </label>
                        </div>
                        """

                    questData.append([
                        "id": [
                            "formatted": String(format: "%03d", rewardType.rawValue),
                            "sort": rewardType.rawValue
                        ],
                        "name": rewardTypeName,
                        "image": "<img class=\"lazy_load\" " +
                            "data-src=\"/image-api/reward?style=\(iconStyle)&id=\(0)&type=\(rewardType.rawValue)\" " +
                            "style=\"height:50px; width:50px;\">",
                        "filter": filter,
                        "size": size,
                        "type": miscTypeString
                    ])
                }
            }
            data["quest_filters"] = questData
        }

        if permViewMap && showRaidFilter {
            let hideString = Localizer.global.get(value: "filter_hide")
            let showString = Localizer.global.get(value: "filter_show")

            let smallString = Localizer.global.get(value: "filter_small")
            let normalString = Localizer.global.get(value: "filter_normal")
            let largeString = Localizer.global.get(value: "filter_large")
            let hugeString = Localizer.global.get(value: "filter_huge")

            let generalString = Localizer.global.get(value: "filter_general")
            let raidLevelsString = Localizer.global.get(value: "filter_raid_levels")
            let pokemonString = Localizer.global.get(value: "filter_pokemon")

            var raidData = [[String: Any]]()

            let raidTimers = Localizer.global.get(value: "filter_raid_timers")

            let filter = """
            <div class="btn-group btn-group-toggle" data-toggle="buttons">
            <label class="btn btn-sm btn-off select-button-new" data-id="timers"
             data-type="raid-timers" data-info="hide">
            <input type="radio" name="options" id="hide" autocomplete="off">\(hideString)
            </label>
            <label class="btn btn-sm btn-on select-button-new" data-id="timers"
             data-type="raid-timers" data-info="show">
            <input type="radio" name="options" id="show" autocomplete="off">\(showString)
            </label>
            </div>
            """

            let size = """
            <div class="btn-group btn-group-toggle" data-toggle="buttons">
            <label class="btn btn-sm btn-size select-button-new" data-id="timers"
             data-type="raid-timers" data-info="small" disabled>
            <input type="radio" name="options" id="hide" autocomplete="off">\(smallString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="timers"
             data-type="raid-timers" data-info="normal" disabled>
            <input type="radio" name="options" id="show" autocomplete="off">\(normalString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="timers"
             data-type="raid-timers" data-info="large" disabled>
            <input type="radio" name="options" id="show" autocomplete="off">\(largeString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="timers"
             data-type="raid-timers" data-info="huge" disabled>
            <input type="radio" name="options" id="show" autocomplete="off">\(hugeString)
            </label>
            </div>
            """

            raidData.append([
                "id": [
                    "formatted": String(format: "%03d", 0),
                    "sort": 0
                ],
                "name": raidTimers,
                "image": "<img class=\"lazy_load\" data-src=\"/static/misc/timer.png\" " +
                         "style=\"height:50px; width:50px;\">",
                "filter": filter,
                "size": size,
                "type": generalString
                ])

            // Level
            for i in [1, 3, 4, 5, 6, 7, 8, 9] {

                let raidLevel = Localizer.global.get(value: "filter_raid_level_\(i)")

                let filter = """
                <div class="btn-group btn-group-toggle" data-toggle="buttons">
                <label class="btn btn-sm btn-off select-button-new" data-id="\(i)"
                 data-type="raid-level" data-info="hide">
                <input type="radio" name="options" id="hide" autocomplete="off">\(hideString)
                </label>
                <label class="btn btn-sm btn-on select-button-new" data-id="\(i)"
                 data-type="raid-level" data-info="show">
                <input type="radio" name="options" id="show" autocomplete="off">\(showString)
                </label>
                </div>
                """

                let size = """
                <div class="btn-group btn-group-toggle" data-toggle="buttons">
                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                 data-type="raid-level" data-info="small">
                <input type="radio" name="options" id="hide" autocomplete="off">\(smallString)
                </label>
                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                 data-type="raid-level" data-info="normal">
                <input type="radio" name="options" id="show" autocomplete="off">\(normalString)
                </label>
                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                 data-type="raid-level" data-info="large">
                <input type="radio" name="options" id="show" autocomplete="off">\(largeString)
                </label>
                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                 data-type="raid-level" data-info="huge">
                <input type="radio" name="options" id="show" autocomplete="off">\(hugeString)
                </label>
                </div>
                """

                raidData.append([
                    "id": [
                        "formatted": String(format: "%03d", i),
                        "sort": i
                    ],
                    "name": raidLevel,
                    "image": "<img class=\"lazy_load\" data-src=\"/image-api/raid-egg?style=\(iconStyle)&id=\(i)\" " +
                             "style=\"height:50px; width:50px;\">",
                    "filter": filter,
                    "size": size,
                    "type": raidLevelsString
                ])
            }

            // Pokemon
            for i in 1...WebRequestHandler.maxPokemonId {

                let filter = """
                <div class="btn-group btn-group-toggle" data-toggle="buttons">
                <label class="btn btn-sm btn-off select-button-new" data-id="\(i)"
                 data-type="raid-pokemon" data-info="hide">
                <input type="radio" name="options" id="hide" autocomplete="off">\(hideString)
                </label>
                <label class="btn btn-sm btn-on select-button-new" data-id="\(i)"
                 data-type="raid-pokemon" data-info="show">
                <input type="radio" name="options" id="show" autocomplete="off">\(showString)
                </label>
                </div>
                """

                let size = """
                <div class="btn-group btn-group-toggle" data-toggle="buttons">
                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                 data-type="raid-pokemon" data-info="small">
                <input type="radio" name="options" id="hide" autocomplete="off">\(smallString)
                </label>
                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                 data-type="raid-pokemon" data-info="normal">
                <input type="radio" name="options" id="show" autocomplete="off">\(normalString)
                </label>
                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                 data-type="raid-pokemon" data-info="large">
                <input type="radio" name="options" id="show" autocomplete="off">\(largeString)
                </label>
                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                 data-type="raid-pokemon" data-info="huge">
                <input type="radio" name="options" id="show" autocomplete="off">\(hugeString)
                </label>
                </div>
                """
                raidData.append([
                    "id": [
                        "formatted": String(format: "%03d", i),
                        "sort": i+200
                    ],
                    "name": Localizer.global.get(value: "poke_\(i)"),
                    "image": "<img class=\"lazy_load\" data-src=\"/image-api/pokemon?style=\(iconStyle)&id=\(i)\" " +
                             "style=\"height:50px; width:50px;\">",
                    "filter": filter,
                    "size": size,
                    "type": pokemonString
                ])
            }

            data["raid_filters"] = raidData
        }

        if permViewMap && showGymFilter {
            let hideString = Localizer.global.get(value: "filter_hide")
            let showString = Localizer.global.get(value: "filter_show")

            let smallString = Localizer.global.get(value: "filter_small")
            let normalString = Localizer.global.get(value: "filter_normal")
            let largeString = Localizer.global.get(value: "filter_large")
            let hugeString = Localizer.global.get(value: "filter_huge")

            let gymTeamString = Localizer.global.get(value: "filter_gym_team")
            let gymOptionsString = Localizer.global.get(value: "filter_gym_options")
            let availableSlotsString = Localizer.global.get(value: "filter_gym_available_slots")
            let powerUpLevelString = Localizer.global.get(value: "filter_poi_power_up_level")

            var gymData = [[String: Any]]()
            // Team
            for i in 0...3 {

                let gymTeam = Localizer.global.get(value: "filter_gym_team_\(i)")

                let filter = """
                <div class="btn-group btn-group-toggle" data-toggle="buttons">
                <label class="btn btn-sm btn-off select-button-new" data-id="\(i)"
                 data-type="gym-team" data-info="hide">
                <input type="radio" name="options" id="hide" autocomplete="off">\(hideString)
                </label>
                <label class="btn btn-sm btn-on select-button-new" data-id="\(i)"
                 data-type="gym-team" data-info="show">
                <input type="radio" name="options" id="show" autocomplete="off">\(showString)
                </label>
                </div>
                """

                let size = """
                <div class="btn-group btn-group-toggle" data-toggle="buttons">
                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                 data-type="gym-team" data-info="small">
                <input type="radio" name="options" id="hide" autocomplete="off">\(smallString)
                </label>
                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                 data-type="gym-team" data-info="normal">
                <input type="radio" name="options" id="show" autocomplete="off">\(normalString)
                </label>
                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                 data-type="gym-team" data-info="large">
                <input type="radio" name="options" id="show" autocomplete="off">\(largeString)
                </label>
                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                 data-type="gym-team" data-info="huge">
                <input type="radio" name="options" id="show" autocomplete="off">\(hugeString)
                </label>
                </div>
                """

                gymData.append([
                    "id": [
                        "formatted": String(format: "%03d", i),
                        "sort": i
                    ],
                    "name": gymTeam,
                    "image": "<img class=\"lazy_load\" data-src=\"/image-api/gym?style=\(iconStyle)" +
                        "&id=\(i)&level=\(i)\" style=\"height:50px; width:50px;\">",
                    "filter": filter,
                    "size": size,
                    "type": gymTeamString
                ])
            }

            // EX raid eligible gyms
            let exFilter = """
            <div class="btn-group btn-group-toggle" data-toggle="buttons">
            <label class="btn btn-sm btn-off select-button-new" data-id="ex" data-type="gym-ex" data-info="hide">
            <input type="radio" name="options" id="hide" autocomplete="off">\(hideString)
            </label>
            <label class="btn btn-sm btn-on select-button-new" data-id="ex" data-type="gym-ex" data-info="show">
            <input type="radio" name="options" id="show" autocomplete="off">\(showString)
            </label>
            </div>
            """

            let exSize = """
            <div class="btn-group btn-group-toggle" data-toggle="buttons">
            <label class="btn btn-sm btn-size select-button-new" data-id="ex" data-type="gym-ex" data-info="small">
            <input type="radio" name="options" id="hide" autocomplete="off">\(smallString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="ex" data-type="gym-ex" data-info="normal">
            <input type="radio" name="options" id="show" autocomplete="off">\(normalString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="ex" data-type="gym-ex" data-info="large">
            <input type="radio" name="options" id="show" autocomplete="off">\(largeString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="ex" data-type="gym-ex" data-info="huge">
            <input type="radio" name="options" id="show" autocomplete="off">\(hugeString)
            </label>
            </div>
            """

            gymData.append([
                "id": [
                    "formatted": String(format: "%03d", 5), // Need a better way to display, new section?
                    "sort": 5
                ],
                "name": Localizer.global.get(value: "filter_raid_ex") ,
                "image": "<img class=\"lazy_load\" data-src=\"/image-api/reward?style=\(iconStyle)&id=1403&type=2\" " +
                         "style=\"height:50px; width:50px;\">",
                "filter": exFilter,
                "size": exSize,
                "type": gymOptionsString
            ])

            // AR gyms
            let arFilter = """
            <div class="btn-group btn-group-toggle" data-toggle="buttons">
            <label class="btn btn-sm btn-off select-button-new" data-id="ar" data-type="gym-ar" data-info="hide">
            <input type="radio" name="options" id="hide" autocomplete="off">\(hideString)
            </label>
            <label class="btn btn-sm btn-on select-button-new" data-id="ar" data-type="gym-ar" data-info="show">
            <input type="radio" name="options" id="show" autocomplete="off">\(showString)
            </label>
            </div>
            """

            let arSize = """
            <div class="btn-group btn-group-toggle" data-toggle="buttons">
            <label class="btn btn-sm btn-size select-button-new" data-id="ar" data-type="gym-ar" data-info="small">
            <input type="radio" name="options" id="hide" autocomplete="off">\(smallString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="ar" data-type="gym-ar" data-info="normal">
            <input type="radio" name="options" id="show" autocomplete="off">\(normalString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="ar" data-type="gym-ar" data-info="large">
            <input type="radio" name="options" id="show" autocomplete="off">\(largeString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="ar" data-type="gym-ar" data-info="huge">
            <input type="radio" name="options" id="show" autocomplete="off">\(hugeString)
            </label>
            </div>
            """

            gymData.append([
                "id": [
                    "formatted": String(format: "%03d", 6), // Need a better way to display, new section?
                    "sort": 6
                ],
                "name": Localizer.global.get(value: "filter_gym_ar_only") ,
                "image": "<img class=\"lazy_load\" data-src=\"/image-api/misc?style=\(iconStyle)&id=ar\" " +
                        "style=\"height:50px; width:50px;\">",
                "filter": arFilter,
                "size": arSize,
                "type": gymOptionsString
            ])

            // Sponsored gyms
            let sponsoredFilter = """
            <div class="btn-group btn-group-toggle" data-toggle="buttons">
            <label class="btn btn-sm btn-off select-button-new" data-id="sponsored" data-type="gym-sponsored"
                                data-info="hide">
            <input type="radio" name="options" id="hide" autocomplete="off">\(hideString)
            </label>
            <label class="btn btn-sm btn-on select-button-new" data-id="sponsored" data-type="gym-sponsored"
                                data-info="show">
            <input type="radio" name="options" id="show" autocomplete="off">\(showString)
            </label>
            </div>
            """

            let sponsoredSize = """
            <div class="btn-group btn-group-toggle" data-toggle="buttons">
            <label class="btn btn-sm btn-size select-button-new" data-id="sponsored" data-type="gym-sponsored"
                                data-info="small">
            <input type="radio" name="options" id="hide" autocomplete="off">\(smallString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="sponsored" data-type="gym-sponsored"
                                data-info="normal">
            <input type="radio" name="options" id="show" autocomplete="off">\(normalString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="sponsored" data-type="gym-sponsored"
                                data-info="large">
            <input type="radio" name="options" id="show" autocomplete="off">\(largeString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="sponsored" data-type="gym-sponsored"
                                data-info="huge">
            <input type="radio" name="options" id="show" autocomplete="off">\(hugeString)
            </label>
            </div>
            """

            gymData.append([
                "id": [
                    "formatted": String(format: "%03d", 7), // Need a better way to display, new section?
                    "sort": 7
                ],
                "name": Localizer.global.get(value: "filter_gym_sponsored_only") ,
                "image": "<img class=\"lazy_load\" data-src=\"/image-api/misc?style=\(iconStyle)&id=sponsor\" " +
                        "style=\"height:50px; width:50px;\">",
                "filter": sponsoredFilter,
                "size": sponsoredSize,
                "type": gymOptionsString
            ])

            // Powered-up gyms
            for i in 0...3 {
                let powerUpLevel = Localizer.global.get(value: "filter_poi_power_up_level_\(i)")
                let powerUpFilter = """
                <div class="btn-group btn-group-toggle" data-toggle="buttons">
                <label class="btn btn-sm btn-off select-button-new" data-id="\(i)"
                                      data-type="gym-power-up" data-info="hide">
                <input type="radio" name="options" id="hide" autocomplete="off">\(hideString)
                </label>
                <label class="btn btn-sm btn-on select-button-new" data-id="\(i)"
                                      data-type="gym-power-up" data-info="show">
                <input type="radio" name="options" id="show" autocomplete="off">\(showString)
                </label>
                </div>
                """

                let powerUpSize = """
                <div class="btn-group btn-group-toggle" data-toggle="buttons">
                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                                    data-type="gym-power-up" data-info="small">
                <input type="radio" name="options" id="hide" autocomplete="off">\(smallString)
                </label>
                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                                    data-type="gym-power-up" data-info="normal">
                <input type="radio" name="options" id="show" autocomplete="off">\(normalString)
                </label>
                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                                    data-type="gym-power-up" data-info="large">
                <input type="radio" name="options" id="show" autocomplete="off">\(largeString)
                </label>
                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                                    data-type="gym-power-up" data-info="huge">
                <input type="radio" name="options" id="show" autocomplete="off">\(hugeString)
                </label>
                </div>
                """

                let team = (UInt16.random % 3) + 1

                gymData.append([
                    "id": [
                        "formatted": String(format: "%03d", i),
                        "sort": i+10
                    ],
                    "name": powerUpLevel,
                    "image": "<img class=\"lazy_load\" " +
                        "data-src=\"/image-api/gym?style=\(iconStyle)&id=\(i == 0 ? 0 : team)&level=\(i)\" " +
                        "style=\"height:50px; width:50px;\">",
                    "filter": powerUpFilter,
                    "size": powerUpSize,
                    "type": powerUpLevelString
                ])
            }

            // Available slots
            for i in 0...6 {
                let availableSlots = Localizer.global.get(value: "filter_gym_available_slots_\(i)")

                let filter = """
                <div class="btn-group btn-group-toggle" data-toggle="buttons">
                <label class="btn btn-sm btn-off select-button-new" data-id="\(i)"
                 data-type="gym-slots" data-info="hide">
                <input type="radio" name="options" id="hide" autocomplete="off">\(hideString)
                </label>
                <label class="btn btn-sm btn-on select-button-new" data-id="\(i)"
                 data-type="gym-slots" data-info="show">
                <input type="radio" name="options" id="show" autocomplete="off">\(showString)
                </label>
                </div>
                """

                let size = """
                <div class="btn-group btn-group-toggle" data-toggle="buttons">
                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                 data-type="gym-slots" data-info="small" disabled>
                <input type="radio" name="options" id="hide" autocomplete="off">\(smallString)
                </label>
                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                 data-type="gym-slots" data-info="normal" disabled>
                <input type="radio" name="options" id="show" autocomplete="off">\(normalString)
                </label>
                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                 data-type="gym-slots" data-info="large" disabled>
                <input type="radio" name="options" id="show" autocomplete="off">\(largeString)
                </label>
                <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                 data-type="gym-slots" data-info="huge" disabled>
                <input type="radio" name="options" id="show" autocomplete="off">\(hugeString)
                </label>
                </div>
                """

                let team = (UInt16.random % 3) + 1

                gymData.append([
                    "id": [
                        "formatted": String(format: "%03d", i),
                        "sort": i+100
                    ],
                    "name": availableSlots,
                    "image": "<img class=\"lazy_load\" " +
                        "data-src=\"/image-api/gym?style=\(iconStyle)&id=\(i == 6 ? 0 : team)&level=\(6 - i)\" " +
                        "style=\"height:50px; width:50px;\">",
                    "filter": filter,
                    "size": size,
                    "type": availableSlotsString
                ])
            }

            data["gym_filters"] = gymData
        }

        if permViewMap && showInvasionFilter {
            let hideString = Localizer.global.get(value: "filter_hide")
            let showString = Localizer.global.get(value: "filter_show")

            let smallString = Localizer.global.get(value: "filter_small")
            let normalString = Localizer.global.get(value: "filter_normal")
            let largeString = Localizer.global.get(value: "filter_large")
            let hugeString = Localizer.global.get(value: "filter_huge")

            let invasionTypeString = Localizer.global.get(value: "filter_invasion_grunt_type")

            var invasionData = [[String: Any]]()
            let filteredGrunts = [1...7, 10...44, 47...50, 500...510].joined()
            for i in filteredGrunts {
                let grunt = Localizer.global.get(value: "grunt_\(i)")

                let filter = """
                             <div class="btn-group btn-group-toggle" data-toggle="buttons">
                             <label class="btn btn-sm btn-off select-button-new" data-id="\(i)"
                              data-type="invasion" data-info="hide">
                             <input type="radio" name="options" id="hide" autocomplete="off">\(hideString)
                             </label>
                             <label class="btn btn-sm btn-on select-button-new" data-id="\(i)"
                              data-type="invasion" data-info="show">
                             <input type="radio" name="options" id="show" autocomplete="off">\(showString)
                             </label>
                             </div>
                             """

                let size = """
                           <div class="btn-group btn-group-toggle" data-toggle="buttons">
                           <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                            data-type="invasion" data-info="small">
                           <input type="radio" name="options" id="hide" autocomplete="off">\(smallString)
                           </label>
                           <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                            data-type="invasion" data-info="normal">
                           <input type="radio" name="options" id="show" autocomplete="off">\(normalString)
                           </label>
                           <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                            data-type="invasion" data-info="large">
                           <input type="radio" name="options" id="show" autocomplete="off">\(largeString)
                           </label>
                           <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                            data-type="invasion" data-info="huge">
                           <input type="radio" name="options" id="show" autocomplete="off">\(hugeString)
                           </label>
                           </div>
                           """

                invasionData.append([
                    "id": [
                        "formatted": String(format: "%03d", i),
                        "sort": i
                    ],
                    "name": grunt,
                    "image": "<img class=\"lazy_load\" data-src=\"/image-api/invasion?style=\(iconStyle)&id=\(i)\" " +
                        "style=\"height:50px; width:50px;\">",
                    "filter": filter,
                    "size": size,
                    "type": invasionTypeString
                ])
            }

            data["invasion_filters"] = invasionData
        }

        if permViewMap && showPokestopFilter {
            let hideString = Localizer.global.get(value: "filter_hide")
            let showString = Localizer.global.get(value: "filter_show")

            let smallString = Localizer.global.get(value: "filter_small")
            let normalString = Localizer.global.get(value: "filter_normal")
            let largeString = Localizer.global.get(value: "filter_large")
            let hugeString = Localizer.global.get(value: "filter_huge")

            let pokestopOptionsString = Localizer.global.get(value: "filter_pokestop_options")

            var pokestopData = [[String: Any]]()

            let pokestopNormal = Localizer.global.get(value: "filter_pokestop_normal")
            let arOnly = Localizer.global.get(value: "filter_pokestop_ar_only")
            let sponsoredOnly = Localizer.global.get(value: "filter_pokestop_sponsored_only")
            let powerUpLevelString = Localizer.global.get(value: "filter_poi_power_up_level")

            let filter = """
            <div class="btn-group btn-group-toggle" data-toggle="buttons">
            <label class="btn btn-sm btn-off select-button-new" data-id="normal"
             data-type="pokestop-normal" data-info="hide">
            <input type="radio" name="options" id="hide" autocomplete="off">\(hideString)
            </label>
            <label class="btn btn-sm btn-on select-button-new" data-id="normal"
             data-type="pokestop-normal" data-info="show">
            <input type="radio" name="options" id="show" autocomplete="off">\(showString)
            </label>
            </div>
            """

            let size = """
            <div class="btn-group btn-group-toggle" data-toggle="buttons">
            <label class="btn btn-sm btn-size select-button-new" data-id="normal"
             data-type="pokestop-normal" data-info="small">
            <input type="radio" name="options" id="hide" autocomplete="off">\(smallString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="normal"
             data-type="pokestop-normal" data-info="normal">
            <input type="radio" name="options" id="show" autocomplete="off">\(normalString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="normal"
             data-type="pokestop-normal" data-info="large">
            <input type="radio" name="options" id="show" autocomplete="off">\(largeString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="normal"
             data-type="pokestop-normal" data-info="huge">
            <input type="radio" name="options" id="show" autocomplete="off">\(hugeString)
            </label>
            </div>
            """

            pokestopData.append([
                "id": [
                    "formatted": String(format: "%03d", 0),
                    "sort": 0
                ],
                "name": pokestopNormal,
                "image": "<img class=\"lazy_load\" data-src=\"/image-api/pokestop?style=\(iconStyle)&id=0\" " +
                         "style=\"height:50px; width:50px;\">",
                "filter": filter,
                "size": size,
                "type": pokestopOptionsString
            ])

            for i in 1...5 {
                let pokestopLure = Localizer.global.get(value: "filter_pokestop_lure_\(i)")

                let lureId: Int
                if i == 1 {
                    lureId = 501
                } else if i == 2 {
                    lureId = 502
                } else if i == 3 {
                    lureId = 503
                } else if i == 4 {
                    lureId = 504
                } else {
                    lureId = 505
                }

                let filter = """
                <div class="btn-group btn-group-toggle" data-toggle="buttons">
                <label class="btn btn-sm btn-off select-button-new" data-id="\(lureId)"
                 data-type="pokestop-lure" data-info="hide">
                <input type="radio" name="options" id="hide" autocomplete="off">\(hideString)
                </label>
                <label class="btn btn-sm btn-on select-button-new" data-id="\(lureId)"
                 data-type="pokestop-lure" data-info="show">
                <input type="radio" name="options" id="show" autocomplete="off">\(showString)
                </label>
                </div>
                """

                let size = """
                <div class="btn-group btn-group-toggle" data-toggle="buttons">
                <label class="btn btn-sm btn-size select-button-new" data-id="\(lureId)"
                 data-type="pokestop-lure" data-info="small">
                <input type="radio" name="options" id="hide" autocomplete="off">\(smallString)
                </label>
                <label class="btn btn-sm btn-size select-button-new" data-id="\(lureId)"
                 data-type="pokestop-lure" data-info="normal">
                <input type="radio" name="options" id="show" autocomplete="off">\(normalString)
                </label>
                <label class="btn btn-sm btn-size select-button-new" data-id="\(lureId)"
                 data-type="pokestop-lure" data-info="large">
                <input type="radio" name="options" id="show" autocomplete="off">\(largeString)
                </label>
                <label class="btn btn-sm btn-size select-button-new" data-id="\(lureId)"
                 data-type="pokestop-lure" data-info="huge">
                <input type="radio" name="options" id="show" autocomplete="off">\(hugeString)
                </label>
                </div>
                """

                pokestopData.append([
                    "id": [
                        "formatted": String(format: "%03d", i),
                        "sort": i
                    ],
                    "name": pokestopLure,
                    "image": "<img class=\"lazy_load\" data-src=\"/image-api/pokestop?style=\(iconStyle)" +
                        "&id=\(lureId)\" style=\"height:50px; width:50px;\">",
                    "filter": filter,
                    "size": size,
                    "type": pokestopOptionsString
                ])
            }

            // Powered-up pokestops
            for i in 0...3 {
                let powerUpLevel = Localizer.global.get(value: "filter_poi_power_up_level_\(i)")
                let powerUpFilter = """
                                    <div class="btn-group btn-group-toggle" data-toggle="buttons">
                                    <label class="btn btn-sm btn-off select-button-new" data-id="\(i)"
                                                          data-type="pokestop-power-up" data-info="hide">
                                    <input type="radio" name="options" id="hide" autocomplete="off">\(hideString)
                                    </label>
                                    <label class="btn btn-sm btn-on select-button-new" data-id="\(i)"
                                                          data-type="pokestop-power-up" data-info="show">
                                    <input type="radio" name="options" id="show" autocomplete="off">\(showString)
                                    </label>
                                    </div>
                                    """

                let powerUpSize = """
                                  <div class="btn-group btn-group-toggle" data-toggle="buttons">
                                  <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                                                      data-type="pokestop-power-up" data-info="small">
                                  <input type="radio" name="options" id="hide" autocomplete="off">\(smallString)
                                  </label>
                                  <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                                                      data-type="pokestop-power-up" data-info="normal">
                                  <input type="radio" name="options" id="show" autocomplete="off">\(normalString)
                                  </label>
                                  <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                                                      data-type="pokestop-power-up" data-info="large">
                                  <input type="radio" name="options" id="show" autocomplete="off">\(largeString)
                                  </label>
                                  <label class="btn btn-sm btn-size select-button-new" data-id="\(i)"
                                                      data-type="pokestop-power-up" data-info="huge">
                                  <input type="radio" name="options" id="show" autocomplete="off">\(hugeString)
                                  </label>
                                  </div>
                                  """

                pokestopData.append([
                    "id": [
                        "formatted": String(format: "%03d", i),
                        "sort": i+10
                    ],
                    "name": powerUpLevel,
                    "image": "<img class=\"lazy_load\" data-src=\"/image-api/pokestop?style=\(iconStyle)&id=0\" " +
                        "style=\"height:50px; width:50px;\">",
                    "filter": powerUpFilter,
                    "size": powerUpSize,
                    "type": powerUpLevelString
                ])
            }

            // AR pokestop
            let arFilter = """
            <div class="btn-group btn-group-toggle" data-toggle="buttons">
            <label class="btn btn-sm btn-off select-button-new" data-id="ar"
             data-type="pokestop-ar" data-info="hide">
            <input type="radio" name="options" id="hide" autocomplete="off">\(hideString)
            </label>
            <label class="btn btn-sm btn-on select-button-new" data-id="ar"
             data-type="pokestop-ar" data-info="show">
            <input type="radio" name="options" id="show" autocomplete="off">\(showString)
            </label>
            </div>
            """

            let arSize = """
            <div class="btn-group btn-group-toggle" data-toggle="buttons">
            <label class="btn btn-sm btn-size select-button-new" data-id="ar"
             data-type="pokestop-ar" data-info="small">
            <input type="radio" name="options" id="hide" autocomplete="off">\(smallString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="ar"
             data-type="pokestop-ar" data-info="normal">
            <input type="radio" name="options" id="show" autocomplete="off">\(normalString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="ar"
             data-type="pokestop-ar" data-info="large">
            <input type="radio" name="options" id="show" autocomplete="off">\(largeString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="ar"
             data-type="pokestop-ar" data-info="huge">
            <input type="radio" name="options" id="show" autocomplete="off">\(hugeString)
            </label>
            </div>
            """

            pokestopData.append([
                "id": [
                    "formatted": String(format: "%03d", 6),
                    "sort": 6
                ],
                "name": arOnly,
                "image": "<img class=\"lazy_load\" data-src=\"/image-api/misc?style=\(iconStyle)&id=ar\" " +
                        "style=\"height:50px; width:50px;\">",
                "filter": arFilter,
                "size": arSize,
                "type": pokestopOptionsString
            ])

            // Sponsored Pokestop
            let sponsoredFilter = """
                           <div class="btn-group btn-group-toggle" data-toggle="buttons">
                           <label class="btn btn-sm btn-off select-button-new" data-id="sponsored"
                            data-type="pokestop-sponsored" data-info="hide">
                           <input type="radio" name="options" id="hide" autocomplete="off">\(hideString)
                           </label>
                           <label class="btn btn-sm btn-on select-button-new" data-id="sponsored"
                            data-type="pokestop-sponsored" data-info="show">
                           <input type="radio" name="options" id="show" autocomplete="off">\(showString)
                           </label>
                           </div>
                           """

            let sponsoredSize = """
                         <div class="btn-group btn-group-toggle" data-toggle="buttons">
                         <label class="btn btn-sm btn-size select-button-new" data-id="sponsored"
                          data-type="pokestop-sponsored" data-info="small">
                         <input type="radio" name="options" id="hide" autocomplete="off">\(smallString)
                         </label>
                         <label class="btn btn-sm btn-size select-button-new" data-id="sponsored"
                          data-type="pokestop-sponsored" data-info="normal">
                         <input type="radio" name="options" id="show" autocomplete="off">\(normalString)
                         </label>
                         <label class="btn btn-sm btn-size select-button-new" data-id="sponsored"
                          data-type="pokestop-sponsored" data-info="large">
                         <input type="radio" name="options" id="show" autocomplete="off">\(largeString)
                         </label>
                         <label class="btn btn-sm btn-size select-button-new" data-id="sponsored"
                          data-type="pokestop-sponsored" data-info="huge">
                         <input type="radio" name="options" id="show" autocomplete="off">\(hugeString)
                         </label>
                         </div>
                         """

            pokestopData.append([
                "id": [
                    "formatted": String(format: "%03d", 7),
                    "sort": 7
                ],
                "name": sponsoredOnly,
                "image": "<img class=\"lazy_load\" data-src=\"/image-api/misc?style=\(iconStyle)&id=sponsor\" " +
                    "style=\"height:50px; width:50px;\">",
                "filter": sponsoredFilter,
                "size": sponsoredSize,
                "type": pokestopOptionsString
            ])

            data["pokestop_filters"] = pokestopData
        }

        if permViewMap && showSpawnpointFilter {
            let hideString = Localizer.global.get(value: "filter_hide")
            let showString = Localizer.global.get(value: "filter_show")

            let smallString = Localizer.global.get(value: "filter_small")
            let normalString = Localizer.global.get(value: "filter_normal")
            let largeString = Localizer.global.get(value: "filter_large")
            let hugeString = Localizer.global.get(value: "filter_huge")

            let spawnpointOptionsString = Localizer.global.get(value: "filter_spawnpoint_options")
            let spawnpointWithTimerString = Localizer.global.get(value: "filter_spawnpoint_with_timer")
            let spawnpointWithoutTimerString = Localizer.global.get(value: "filter_spawnpoint_without_timer")

            var spawnpointData = [[String: Any]]()

            var filter = """
            <div class="btn-group btn-group-toggle" data-toggle="buttons">
            <label class="btn btn-sm btn-off select-button-new" data-id="no-timer"
             data-type="spawnpoint-timer" data-info="hide">
            <input type="radio" name="options" id="hide" autocomplete="off">\(hideString)
            </label>
            <label class="btn btn-sm btn-on select-button-new" data-id="no-timer"
             data-type="spawnpoint-timer" data-info="show">
            <input type="radio" name="options" id="show" autocomplete="off">\(showString)
            </label>
            </div>
            """

            var size = """
            <div class="btn-group btn-group-toggle" data-toggle="buttons">
            <label class="btn btn-sm btn-size select-button-new" data-id="no-timer"
             data-type="spawnpoint-timer" data-info="small">
            <input type="radio" name="options" id="hide" autocomplete="off">\(smallString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="no-timer"
             data-type="spawnpoint-timer" data-info="normal">
            <input type="radio" name="options" id="show" autocomplete="off">\(normalString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="no-timer"
             data-type="spawnpoint-timer" data-info="large">
            <input type="radio" name="options" id="show" autocomplete="off">\(largeString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="no-timer"
             data-type="spawnpoint-timer" data-info="huge">
            <input type="radio" name="options" id="show" autocomplete="off">\(hugeString)
            </label>
            </div>
            """

            spawnpointData.append([
                "id": [
                    "formatted": String(format: "%03d", 0),
                    "sort": 0
                ],
                "name": spawnpointWithoutTimerString,
                "image": "<img class=\"lazy_load\" data-src=\"/image-api/spawnpoint?id=0&style=\(iconStyle)\" " +
                         "style=\"height:50px; width:50px;\">",
                "filter": filter,
                "size": size,
                "type": spawnpointOptionsString
            ])

            filter = """
            <div class="btn-group btn-group-toggle" data-toggle="buttons">
            <label class="btn btn-sm btn-off select-button-new" data-id="with-timer"
             data-type="spawnpoint-timer" data-info="hide">
            <input type="radio" name="options" id="hide" autocomplete="off">\(hideString)
            </label>
            <label class="btn btn-sm btn-on select-button-new" data-id="with-timer"
             data-type="spawnpoint-timer" data-info="show">
            <input type="radio" name="options" id="show" autocomplete="off">\(showString)
            </label>
            </div>
            """

            size = """
            <div class="btn-group btn-group-toggle" data-toggle="buttons">
            <label class="btn btn-sm btn-size select-button-new" data-id="with-timer"
             data-type="spawnpoint-timer" data-info="small">
            <input type="radio" name="options" id="hide" autocomplete="off">\(smallString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="with-timer"
             data-type="spawnpoint-timer" data-info="normal">
            <input type="radio" name="options" id="show" autocomplete="off">\(normalString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="with-timer"
             data-type="spawnpoint-timer" data-info="large">
            <input type="radio" name="options" id="show" autocomplete="off">\(largeString)
            </label>
            <label class="btn btn-sm btn-size select-button-new" data-id="with-timer"
             data-type="spawnpoint-timer" data-info="huge">
            <input type="radio" name="options" id="show" autocomplete="off">\(hugeString)
            </label>
            </div>
            """

            spawnpointData.append([
                "id": [
                    "formatted": String(format: "%03d", 1),
                    "sort": 1
                ],
                "name": spawnpointWithTimerString,
                "image": "<img class=\"lazy_load\" data-src=\"/image-api/spawnpoint?id=1&style=\(iconStyle)\" " +
                         "style=\"height:50px; width:50px;\">",
                "filter": filter,
                "size": size,
                "type": spawnpointOptionsString
            ])

            data["spawnpoint_filters"] = spawnpointData
        }

        if showDevices && perms.contains(.admin) {

            let devices = try? Device.getAll(mysql: mysql)
            var jsonArray = [[String: Any]]()

            if devices != nil {
                for device in devices! {
                    var deviceData = [String: Any]()
                    // deviceData["chk"] = ""
                    deviceData["uuid"] = device.uuid
                    deviceData["host"] = device.lastHost ?? ""
                    deviceData["instance"] = device.instanceName ?? ""
                    deviceData["username"] = device.accountUsername ?? ""

                    if formatted {
                        let formattedDate: String
                        if device.lastSeen == 0 {
                            formattedDate = ""
                        } else {
                            let date = Date(timeIntervalSince1970: TimeInterval(device.lastSeen))
                            let formatter = DateFormatter()
                            formatter.dateFormat = "HH:mm:ss dd.MM.yyy"
                            formatter.timeZone = Localizer.global.timeZone
                            formattedDate = formatter.string(from: date)
                        }
                        deviceData["last_seen"] = ["timestamp": device.lastSeen, "formatted": formattedDate]
                        deviceData["buttons"] = "<a href=\"/dashboard/device/assign/\(device.uuid.encodeUrl()!)\" " +
                                                "role=\"button\" class=\"btn btn-primary\">Assign Instance</a>"
                    } else {
                        deviceData["last_seen"] = device.lastSeen as Any
                    }
                    jsonArray.append(deviceData)
                }
            }
            data["devices"] = jsonArray

        }

        if showInstances && perms.contains(.admin) {

            var totalInstancesCount = 0
            let instances = try? Instance.getAll(mysql: mysql, getData: false)
            var jsonArray = [[String: Any]]()

            if instances != nil {
                for instance in instances! {
                    var instanceData = [String: Any]()
                    instanceData["name"] = instance.name
                    instanceData["count"] = instance.count
                    switch instance.type {
                    case .circleRaid:
                        instanceData["type"] = "Circle Raid"
                    case .circleSmartRaid:
                        instanceData["type"] = "Circle Smart Raid"
                    case .circlePokemon:
                        instanceData["type"] = "Circle Pokemon"
                    case .circleSmartPokemon:
                        instanceData["type"] = "Circle Smart Pokemon"
                    case .autoQuest:
                        instanceData["type"] = "Auto Quest"
                    case .pokemonIV:
                        instanceData["type"] = "Pokemon IV"
                    case .leveling:
                        instanceData["type"] = "Leveling"
                    }

                    let status = skipInstanceStatus ? nil : InstanceController.global.getInstanceStatus(
                        mysql: mysql,
                        instance: instance,
                        formatted: formatted
                    )

                    if status == nil {
                        instanceData["status"] = formatted ? "?" : nil
                    } else {
                        instanceData["status"] = status
                    }

                    if formatted {
                        instanceData["buttons"] = "<a href=\"/dashboard/instance/edit/\(instance.name.encodeUrl()!)\"" +
                            " role=\"button\" class=\"btn btn-primary\">Edit Instance</a>"
                    }
                    jsonArray.append(instanceData)
                }
            }
            data["instances"] = jsonArray
        }

        if showDeviceGroups && perms.contains(.admin) {

            let deviceGroups = try? DeviceGroup.getAll(mysql: mysql)
            let devices = try? Device.getAll(mysql: mysql)

            var jsonArray = [[String: Any]]()

            if deviceGroups != nil {
                for deviceGroup in deviceGroups! {
                    let devicesInGroup = devices?.filter({ deviceGroup.deviceUUIDs.contains($0.uuid) }) ?? []
                    let instances = Array(
                        Set(devicesInGroup.filter({ $0.instanceName != nil }).map({ $0.instanceName! }))
                    ).sorted()

                    var deviceGroupData = [String: Any]()
                    deviceGroupData["name"] = deviceGroup.name

                    if formatted {
                        deviceGroupData["instances"] = instances.joined(separator: ", ")
                        deviceGroupData["devices"] = deviceGroup.deviceUUIDs.joined(separator: ", ")
                        let id = deviceGroup.name.encodeUrl()!
                        deviceGroupData["buttons"] = "<div class=\"btn-group\" role=\"group\"><a " +
                            "href=\"/dashboard/devicegroup/assign/\(id)\" " +
                            "role=\"button\" class=\"btn btn-success\">Assign</a>" +
                            "<a href=\"/dashboard/devicegroup/edit/\(id)\" " +
                            "role=\"button\" class=\"btn btn-primary\">Edit</a>" +
                            "<a href=\"/dashboard/devicegroup/delete/\(id)\" " +
                            "role=\"button\" class=\"btn btn-danger\" onclick=\"return " +
                            "confirm('Are you sure you want to delete this device " +
                            "group? This action is irreversible and cannot be " +
                            "undone without backups.')\">Delete</a></div>"
                    } else {
                        deviceGroupData["instances"] = instances
                        deviceGroupData["devices"] = deviceGroup.deviceUUIDs
                    }

                    jsonArray.append(deviceGroupData)
                }
            }

            data["devicegroups"] = jsonArray
        }

        if showAssignments && perms.contains(.admin) {

            let assignments = try? Assignment.getAll(mysql: mysql)

            var jsonArray = [[String: Any]]()

            if assignments != nil {
                for assignment in assignments! {
                    var assignmentData = [String: Any]()

                    assignmentData["source_instance_name"] = assignment.sourceInstanceName ?? ""
                    assignmentData["instance_name"] = assignment.instanceName
                    assignmentData["device_uuid"] = assignment.deviceUUID ?? ""
                    assignmentData["device_group_name"] = assignment.deviceGroupName ?? ""

                    if formatted {
                        let formattedTime: String
                        if assignment.time == 0 {
                            formattedTime = "On Complete"
                        } else {
                            let times = assignment.time.secondsToHoursMinutesSeconds()
                            formattedTime = "\(String(format: "%02d", times.hours)):" +
                                            "\(String(format: "%02d", times.minutes)):" +
                                            "\(String(format: "%02d", times.seconds))"
                        }
                        assignmentData["time"] = ["timestamp": assignment.time as Any, "formatted": formattedTime]

                        let formattedDate: String
                        if assignment.date == nil {
                            formattedDate = ""
                        } else {
                            formattedDate = assignment.date!.toString() ?? "?"
                        }
                        assignmentData["date"] = [
                            "timestamp": assignment.date?.timeIntervalSince1970 ?? 0,
                            "formatted": formattedDate
                        ]

                        assignmentData["buttons"] = "<div class=\"btn-group\" role=\"group\"><a " +
                            "href=\"/dashboard/assignment/start/\(assignment.id!)\" " +
                            "role=\"button\" class=\"btn btn-success\">Start</a>" +
                            "<a href=\"/dashboard/assignment/edit/\(assignment.id!)\" " +
                            "role=\"button\" class=\"btn btn-primary\">Edit</a>" +
                            "<a href=\"/dashboard/assignment/delete/\(assignment.id!)\" " +
                            "role=\"button\" class=\"btn btn-danger\" onclick=\"return " +
                            "confirm('Are you sure you want to delete this assignment? " +
                            "This action is irreversible and cannot be " +
                            "undone without backups.')\">Delete</a></div>"
                    } else {
                        assignmentData["time"] = assignment.time as Any
                    }
                    assignmentData["enabled"] = assignment.enabled ? "Yes" : "No"

                    jsonArray.append(assignmentData)
                }
            }
            data["assignments"] = jsonArray

        }

        if showAssignmentGroups && perms.contains(.admin) {

            let assignmentGroups = try? AssignmentGroup.getAll(mysql: mysql)
            let assignments = try? Assignment.getAll(mysql: mysql)

            var jsonArray = [[String: Any]]()

            if assignmentGroups != nil {
                for assignmentGroup in assignmentGroups! {
                    let assignmentsInGroup =
                        assignments?.filter({ assignmentGroup.assignmentIDs.contains($0.id!) }) ?? []
                    let assignmentsInGroupDevices = Array(
                        Set(assignmentsInGroup.filter({ $0.deviceUUID != nil || $0.deviceGroupName != nil })
                            .map({ ($0.deviceUUID != nil ? $0.deviceUUID! : "") +
                            ($0.deviceGroupName != nil ? $0.deviceGroupName! : "") + " -> " + $0.instanceName}))
                        ).sorted()

                    var assignmentGroupData = [String: Any]()
                    assignmentGroupData["name"] = assignmentGroup.name
                    assignmentGroupData["assignments"] = assignmentsInGroupDevices.joined(separator: ", ")

                    if formatted {
                        let id = assignmentGroup.name.encodeUrl()!
                        assignmentGroupData["buttons"] = "<div class=\"btn-group\" role=\"group\"><a " +
                            "href=\"/dashboard/assignmentgroup/start/\(id)\" " +
                            "role=\"button\" class=\"btn btn-success\">Start</a>" +
                            "<a href=\"/dashboard/assignmentgroup/request/\(id)\" " +
                            "role=\"button\" class=\"btn btn-warning\" onclick=\"return " +
                            "confirm('Are you sure that you want to clear all quests " +
                            "for this assignment group?')\">ReQuest</a>" +
                            "<a href=\"/dashboard/assignmentgroup/edit/\(id)\" " +
                            "role=\"button\" class=\"btn btn-primary\">Edit</a>" +
                            "<a href=\"/dashboard/assignmentgroup/delete/\(id)\" " +
                            "role=\"button\" class=\"btn btn-danger\" onclick=\"return " +
                            "confirm('Are you sure you want to delete this assignment " +
                            "group? This action is irreversible and cannot be " +
                            "undone without backups.')\">Delete</a></div>"
                    }

                    jsonArray.append(assignmentGroupData)
                }
            }

            data["assignmentgroups"] = jsonArray
        }

        if showWebhooks && perms.contains(.admin) {
            let webhooks = try? Webhook.getAll(mysql: mysql)
            var jsonArray = [[String: Any]]()
            if webhooks != nil {
                for webhook in webhooks! {
                    var webhookData = [String: Any]()
                    webhookData["name"] = webhook.name
                    webhookData["url"] = webhook.url
                    webhookData["delay"] = webhook.delay
                    var types = ""
                    for (index, type) in webhook.types.enumerated() {
                        types.append("\(type.rawValue)")
                        if index != webhook.types.count - 1 {
                            types.append(",")
                        }
                    }
                    webhookData["types"] = types
                    webhookData["enabled"] = webhook.enabled ? "Yes" : "No"

                    if formatted {
                        webhookData["buttons"] = "<div class=\"btn-group\" role=\"group\">" +
                        "<a href=\"/dashboard/webhook/edit/\(webhook.name.encodeUrl()!)\" role=\"button\" " +
                        "class=\"btn btn-primary\">Edit</a>" +
                        "<a href=\"/dashboard/webhook/delete/\(webhook.name.encodeUrl()!)\" role=\"button\" " +
                        "class=\"btn btn-danger\" onclick=\"return " +
                        "confirm('Are you sure you want to delete this webhook? " +
                        "This action is irreversible and cannot be " +
                        "undone without backups.')\">Delete</a></div>"
                    }
                    jsonArray.append(webhookData)
                }
            }
            data["webhooks"] = jsonArray
        }

        if showIVQueue && perms.contains(.admin), let instance = instance {

            let queue = InstanceController.global.getIVQueue(name: instance.decodeUrl() ?? "")

            var jsonArray = [[String: Any]]()
            var i = 1
            for pokemon in queue {

                var json: [String: Any] = [
                    "id": i,
                    "pokemon_id": String(format: "%03d", pokemon.pokemonId),
                    "pokemon_name": Localizer.global.get(value: "poke_\(pokemon.pokemonId)")
                ]
                if formatted {
                    let defaultIconStyle = ImageApiRequestHandler.styles.sorted { (rhs, lhs) -> Bool in
                                rhs.key == "Default" || rhs.key < lhs.key }.first?.key ?? "Default"
                    json["pokemon_image"] =
                        "<img src=\"/image-api/pokemon?style=\(defaultIconStyle)&id=\(pokemon.pokemonId)" +
                        (pokemon.form != nil ? "&form=\(pokemon.form!)" : "") + "\" style=\"height:50px; width:50px;\">"
                    json["pokemon_spawn_id"] =
                        "<a target=\"_blank\" href=\"/@pokemon/\(pokemon.id)\">\(pokemon.id)</a>"
                    json["location"] =
                        "<a target=\"_blank\" href=\"https://www.google.com/maps/place/" +
                        "\(pokemon.lat),\(pokemon.lon)\">\(pokemon.lat),\(pokemon.lon)</a>"
                } else {
                    json["pokemon_spawn_id"] = pokemon.id
                    json["location"] = "\(pokemon.lat), \(pokemon.lon)"
                }
                jsonArray.append(json)
                i += 1
            }
            data["ivqueue"] = jsonArray

        }

        if showUsers && perms.contains(.admin) {
            let users = try? User.getAll(mysql: mysql)
            var jsonArray = [[String: Any]]()

            if users != nil {
                for user in users! {
                    var userData = [String: Any]()
                    userData["username"] = user.username
                    userData["group"] = user.groupName

                    if formatted {
                        if user.emailVerified {
                            userData["email"] = "\(user.email) (Verified)"
                        } else {
                            userData["email"] = user.email
                        }
                        userData["buttons"] = "<a href=\"/dashboard/user/edit/\(user.username.encodeUrl()!)\" " +
                                              "role=\"button\" class=\"btn btn-primary\">Edit User</a>"
                    } else {
                        userData["email"] = user.email
                        userData["email_verified"] = user.emailVerified
                    }
                    jsonArray.append(userData)
                }
            }
            data["users"] = jsonArray
        }

        if showGroups && perms.contains(.admin) {
            let groups = try? Group.getAll(mysql: mysql)
            var jsonArray = [[String: Any]]()

            if groups != nil {
                for group in groups! {
                    var groupData = [String: Any]()
                    groupData["name"] = group.name

                    if formatted {
                        if group.name != "root" {
                            groupData["buttons"] = "<a href=\"/dashboard/group/edit/\(group.name.encodeUrl()!)\" " +
                                                   "role=\"button\" class=\"btn btn-primary\">Edit Group</a>"
                        } else {
                            groupData["buttons"] = ""
                        }
                        var permsString = ""
                        for perm in group.perms {
                            var permName: String
                            switch perm {
                            case .viewMap:
                                permName = "Map"
                            case .viewMapRaid:
                                permName = "Raid"
                            case .viewMapPokemon:
                                permName = "Pokemon"
                            case .viewStats:
                                permName = "Stats"
                            case .admin:
                                permName = "Admin"
                            case .viewMapGym:
                                permName = "Gym"
                            case .viewMapPokestop:
                                permName = "Pokestop"
                            case .viewMapSpawnpoint:
                                permName = "Spawnpoint"
                            case .viewMapQuest:
                                permName = "Quest"
                            case .viewMapIV:
                                permName = "IV"
                            case .viewMapCell:
                                permName = "Scann-Cell"
                            case .viewMapWeather:
                                permName = "Weather"
                            case .viewMapLure:
                                permName = "Lure"
                            case .viewMapInvasion:
                                permName = "Invasion"
                            case .viewMapDevice:
                                permName = "Device"
                            case .viewMapSubmissionCells:
                                permName = "Submission-Cell"
                            case .viewMapEventPokemon:
                                permName = "Event Pokemon"
                            }

                            if permsString == "" {
                                permsString += permName
                            } else {
                                permsString += ","+permName
                            }
                        }
                        groupData["perms"] = permsString

                    } else {
                        groupData["perms"] = Group.Perm.permsToNumber(perms: group.perms)
                    }
                    jsonArray.append(groupData)
                }
            }
            data["groups"] = jsonArray
        }

        if showDiscordRules && perms.contains(.admin) {

            var jsonArray = [[String: Any]]()
            let discordRules = DiscordController.global.getDiscordRules()

            for discordRule in discordRules {
                var discordRuleData = [String: Any]()
                discordRuleData["priority"] = discordRule.priority
                discordRuleData["group_name"] = discordRule.groupName
                if formatted {
                    let serverId = discordRule.serverId
                    let roleId = discordRule.roleId
                    let guilds = DiscordController.global.getAllGuilds()

                    discordRuleData["server"] = [
                        "id": serverId,
                        "name": guilds[serverId]?.name ?? serverId.description
                    ]
                    if roleId != nil {
                        let guild = guilds[serverId]
                        let name = guild?.roles[roleId!] ?? roleId!.description

                        discordRuleData["role"] = [
                            "id": roleId as Any,
                            "name": name
                        ]
                    } else {
                        discordRuleData["role"] = [
                            "id": nil,
                            "name": "Any"
                        ]
                    }
                    discordRuleData["buttons"] = "<a href=\"/dashboard/discordrule/edit/\(discordRule.priority)\" " +
                                                 "role=\"button\" class=\"btn btn-primary\">Edit Discord Rule</a>"
                } else {
                    discordRuleData["server_id"] = discordRule.serverId
                    discordRuleData["role_id"] = discordRule.roleId
                }
                jsonArray.append(discordRuleData)
            }
            data["discordrules"] = jsonArray
        }

        let permViewStats = perms.contains(.viewStats)
        if permViewStats && showDashboardStats {
            let stats = Stats().getJSONValues()
            data["pokemon_total"] = stats["pokemon_total"]
            data["pokemon_iv_total"] = stats["pokemon_iv_total"]
            data["pokemon_total_shiny"] = stats["pokemon_total_shiny"]
            data["pokemon_total_hundo"] = stats["pokemon_total_hundo"]
            data["pokemon_today"] = stats["pokemon_today"]
            data["pokemon_iv_today"] = stats["pokemon_iv_today"]
            data["pokemon_today_shiny"] = stats["pokemon_today_shiny"]
            data["pokemon_today_hundo"] = stats["pokemon_today_hundo"]
            data["pokemon_active"] = stats["pokemon_active"]
            data["pokemon_iv_active"] = stats["pokemon_iv_active"]
            data["pokemon_active_100iv"] = stats["pokemon_active_100iv"]
            data["pokemon_active_90iv"] = stats["pokemon_active_90iv"]
            data["pokemon_active_0iv"] = stats["pokemon_active_0iv"]
            data["pokemon_active_shiny"] = stats["pokemon_active_shiny"]
            data["pokestops_total"] = stats["pokestops_total"]
            data["pokestops_lures_normal"] = stats["pokestops_lures_normal"]
            data["pokestops_lures_glacial"] = stats["pokestops_lures_glacial"]
            data["pokestops_lures_mossy"] = stats["pokestops_lures_mossy"]
            data["pokestops_lures_magnetic"] = stats["pokestops_lures_magnetic"]
            data["pokestops_quests"] = stats["pokestops_quests"]
            data["pokestops_invasions"] = stats["pokestops_invasions"]
            data["pokestops_lures_normal"] = stats["pokestops_lures_normal"]
            data["gyms_total"] = stats["gyms_total"]
            data["gyms_neutral"] = stats["gyms_neutral"]
            data["gyms_mystic"] = stats["gyms_mystic"]
            data["gyms_valor"] = stats["gyms_valor"]
            data["gyms_instinct"] = stats["gyms_instinct"]
            data["gyms_raids"] = stats["gyms_raids"]
            data["spawnpoints_total"] = stats["spawnpoints_total"]
            data["spawnpoints_found"] = stats["spawnpoints_found"]
            data["spawnpoints_missing"] = stats["spawnpoints_missing"]
        }

        if permViewStats && permShowPokemon && showTop10Stats {
            let lifetime = try? Stats.getTopPokemonStats(mysql: mysql, mode: "lifetime")
            let today = try? Stats.getTopPokemonStats(mysql: mysql, mode: "today")
            let month = try? Stats.getTopPokemonStats(mysql: mysql, mode: "month")
            data["lifetime"] = lifetime
            data["today"] = today
            data["month"] = month

            if permShowIV {
                let hundo = try? Stats.getTopPokemonStats(mysql: mysql, mode: "iv")
                data["top10_100iv"] = hundo
            }
        }

        if permViewStats && permShowPokemon && showPokemonStats {
            if date == "lifetime" {
                let stats = try? Stats.getAllPokemonStats(mysql: mysql)
                data["stats"] = stats
            } else {
                let stats = try? Stats.getPokemonIVStats(mysql: mysql, date: date)
                data["date"] = date
                data["stats"] = stats
            }
        }

        if permViewStats && permShowRaid && showRaidStats {
            if date == "lifetime" {
                data["stats"] = try? Stats.getAllRaidStats(mysql: mysql)
            } else {
                data["date"] = date
                data["raid_stats"] = try? Stats.getRaidStats(mysql: mysql, date: date)
                data["egg_stats"] = try? Stats.getRaidEggStats(mysql: mysql, date: date)
            }
        }

        if permViewStats && permShowQuests && showQuestStats {
            if date == "lifetime" {
                data["stats"] = try? Stats.getAllQuestStats(mysql: mysql)
            } else {
                data["date"] = date
                data["quest_item_stats"] = try? Stats.getQuestItemStats(mysql: mysql, date: date)
                data["quest_pokemon_stats"] = try? Stats.getQuestPokemonStats(mysql: mysql, date: date)
            }
        }

        if permViewStats && permShowInvasions && showInvasionStats {
            if date == "lifetime" {
                data["stats"] = try? Stats.getAllInvasionStats(mysql: mysql)
            } else {
                data["stats"] = try? Stats.getInvasionStats(mysql: mysql, date: date)
            }
        }

        if permViewStats && permShowPokemon && showCommdayStats {
            if pokemonId > 0 && !startTimestamp.isEmpty && !endTimestamp.isEmpty {
                let stats = try? Stats.getCommDayStats(mysql: mysql, pokemonId: pokemonId,
                    start: startTimestamp, end: endTimestamp)
                let evo1Name = Localizer.global.get(value: "poke_\(pokemonId)")
                let evo2Name = Localizer.global.get(value: "poke_\(pokemonId + 1)")
                let evo3Name = Localizer.global.get(value: "poke_\(pokemonId + 2)")
                data["pokemon_id"] = pokemonId
                data["evo1_name"] = "\(evo1Name) (#\(pokemonId))"
                data["evo2_name"] = "\(evo2Name) (#\(pokemonId + 1))"
                data["evo3_name"] = "\(evo3Name) (#\(pokemonId + 2))"
                data["start"] = startTimestamp
                data["end"] = endTimestamp
                data["stats"] = stats
            }
        }

        if showStatus && perms.contains(.admin) {
            do {
                let passed = UInt32(Date().timeIntervalSince(self.start)).secondsToDaysHoursMinutesSeconds()
                let devices: [Device] = try Device.getAll(mysql: mysql)
                let offlineDevices = devices.filter {
                    Date().timeIntervalSince(Date(timeIntervalSince1970: Double($0.lastSeen))) >= 15 * 60
                }
                let onlineDevices = devices.filter {
                    Date().timeIntervalSince(Date(timeIntervalSince1970: Double($0.lastSeen))) < 15 * 60
                }
                let activePokemonCounts = try Pokemon.getActiveCounts(mysql: mysql)

                let limits = WebHookRequestHandler.getThreadLimits()
                data["status"] = [
                    "processing": [
                        "current": limits.current,
                        "total": limits.total,
                        "ignored": limits.ignored,
                        "max": WebHookRequestHandler.threadLimitMax
                    ],
                    "uptime": [
                        "date": self.start.timeIntervalSince1970,
                        "days": passed.days,
                        "hours": passed.hours,
                        "minutes": passed.minutes,
                        "seconds": passed.seconds
                    ],
                    "devices": [
                        "total": devices.count,
                        "offline": offlineDevices.count,
                        "online": onlineDevices.count
                    ],
                    "pokemon": [
                        "active_total": activePokemonCounts.total,
                        "active_iv": activePokemonCounts.iv
                    ]
                ]
            } catch {
                response.respondWithError(status: .internalServerError)
                return
            }
        }

        if scanNext && queueSize && perms.contains(.admin), let name = instance {
            guard let instance = InstanceController.global.getInstanceController(instanceName: name.decodeUrl() ?? ""),
                  instance is CircleInstanceController || instance is IVInstanceController
            else {
                Log.error(message: "[ApiRequestHandler] Instance '\(name.decodeUrl() ?? "")' not found " +
                    "or it's no Circle or IV Instance")
                return response.respondWithError(status: .custom(code: 404,
                    message: "Instance not found or of wrong type"))
            }
            let size = instance.getNextCoordsSize()
            data["size"] = size
        }

        do {
            if data.isEmpty {
                response.respondWithError(status: .badRequest)
                return
            }
            data["timestamp"] = Int(Date().timeIntervalSince1970)
            try response.respondWithData(data: data)
        } catch {
            response.respondWithError(status: .internalServerError)
            return
        }
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private static func handleSetData(request: HTTPRequest, response: HTTPResponse) {

        guard let perms = getPerms(request: request, response: response, route: WebServer.APIPage.setData) else {
            return
        }
        let jsonDecoder = JSONDecoder()
        let setGymName = request.param(name: "set_gym_name")?.toBool() ?? false
        let gymId = request.param(name: "gym_id")
        let gymName = request.param(name: "gym_name")
        let setPokestopName = request.param(name: "set_pokestop_name")?.toBool() ?? false
        let pokestopId = request.param(name: "pokestop_id")
        let pokestopName = request.param(name: "pokestop_name")
        let reloadInstances = request.param(name: "reload_instances")?.toBool() ?? false
        let clearAllQuests = request.param(name: "clear_all_quests")?.toBool() ?? false
        let assignDeviceGroup = request.param(name: "assign_devicegroup")?.toBool() ?? false
        let deviceGroupName = request.param(name: "devicegroup_name")
        let assignDevice = request.param(name: "assign_device")?.toBool() ?? false
        let deviceName = request.param(name: "device_name")
        let instanceName = request.param(name: "instance_name") // MARK: remove this later, use 'instance' instead
        let instance = request.param(name: "instance") ?? instanceName
        let assignmentGroupReQuest = request.param(name: "assignmentgroup_re_quest")?.toBool() ?? false
        let assignmentGroupStart = request.param(name: "assignmentgroup_start")?.toBool() ?? false
        let assignmentGroupName = request.param(name: "assignmentgroup_name")
        let clearMemCache = request.param(name: "clear_memcache")?.toBool() ?? false

        let scanNext = request.param(name: "scan_next")?.toBool() ?? false
        let coords = try? jsonDecoder.decode([Coord].self,
            from: request.param(name: "coords")?.data(using: .utf8) ?? Data())

        if setGymName, perms.contains(.admin), let id = gymId, let name = gymName {
            do {
                guard let oldGym = try Gym.getWithId(id: id, copy: true) else {
                    return response.respondWithError(status: .custom(code: 404, message: "Gym not found"))
                }
                oldGym.name = name
                try oldGym.save()
                response.respondWithOk()
            } catch {
                response.respondWithError(status: .internalServerError)
            }
        } else if setPokestopName, perms.contains(.admin), let id = pokestopId, let name = pokestopName {
           do {
               guard let oldPokestop = try Pokestop.getWithId(id: id, copy: true) else {
                   return response.respondWithError(status: .custom(code: 404, message: "Pokestop not found"))
               }
               oldPokestop.name = name
               try oldPokestop.save()
               response.respondWithOk()
           } catch {
               response.respondWithError(status: .internalServerError)
           }
	    } else if reloadInstances && perms.contains(.admin) {
           do {
               Log.info(message: "[ApiRequestHandler] API request to restart all instances.")
               try InstanceController.setup()
               response.respondWithOk()
           } catch {
               response.respondWithError(status: .internalServerError)
           }
        } else if clearAllQuests && perms.contains(.admin) {
            do {
                Log.info(message: "[ApiRequestHandler] API request to clear all quests")
                try Pokestop.clearQuests()
                response.respondWithOk()
            } catch {
                response.respondWithError(status: .internalServerError)
            }
        } else if assignDeviceGroup && perms.contains(.admin), let name = deviceGroupName, let goal = instance {
            do {
                Log.info(message: "[ApiRequestHandler] API request to assign devicegroup \(name) to instance \(goal)")
                guard let deviceGroup = try DeviceGroup.getByName(name: name),
                      let instance = try Instance.getByName(name: goal) else {
                    return response.respondWithError(status: .notFound)
                }
                let devices = try Device.getAllInGroup(deviceGroupName: deviceGroup.name)
                for device in devices {
                    device.instanceName = instance.name
                    try device.save(oldUUID: device.uuid)
                    InstanceController.global.reloadDevice(newDevice: device, oldDeviceUUID: device.uuid)
                }
                response.respondWithOk()
            } catch {
                response.respondWithError(status: .internalServerError)
            }
        } else if assignDevice && perms.contains(.admin), let name = deviceName, let goal = instance {
            do {
                Log.info(message: "[ApiRequestHandler] API request to assign device \(name) to instance \(goal)")
                guard let device = try Device.getById(id: name),
                      let instance = try Instance.getByName(name: goal) else {
                    return response.respondWithError(status: .notFound)
                }
                device.instanceName = instance.name
                try device.save(oldUUID: device.uuid)
                InstanceController.global.reloadDevice(newDevice: device, oldDeviceUUID: device.uuid)
                response.respondWithOk()
            } catch {
                response.respondWithError(status: .internalServerError)
            }
        } else if assignmentGroupReQuest && perms.contains(.admin), let name = assignmentGroupName {
            do {
                Log.info(message: "[ApiRequestHandler] API request to reQuest assignment group \(name)")
                guard let assignmentGroup = try AssignmentGroup.getByName(name: name) else {
                    return response.respondWithError(status: .notFound)
                }
                try AssignmentController.global.reQuestAssignmentGroup(assignmentGroup: assignmentGroup)
                response.respondWithOk()
            } catch {
                Log.error(message: "[ApiRequestHandler] API request to reQuest was not successful")
                response.respondWithError(status: .internalServerError)
            }
        } else if assignmentGroupStart && perms.contains(.admin), let name = assignmentGroupName {
            do {
                Log.info(message: "[ApiRequestHandler] API request to start assignment group \(name)")
                guard let assignmentGroup = try AssignmentGroup.getByName(name: name) else {
                    return response.respondWithError(status: .notFound)
                }
                try AssignmentController.global.startAssignmentGroup(assignmentGroup: assignmentGroup)
                response.respondWithOk()
            } catch {
                response.respondWithError(status: .internalServerError)
            }
        } else if scanNext && perms.contains(.admin), let name = instance, let coords = coords {
            Log.info(message: "[ApiRequestHandler] API request to scan next coordinates with instance '\(name)'")
            guard var instance = InstanceController.global.getInstanceController(instanceName: name.decodeUrl() ?? ""),
                  instance is CircleInstanceController || instance is IVInstanceController
            else {
                Log.error(message: "[ApiRequestHandler] Instance '\(name)' not found " +
                    "or it's no Circle or IV Instance")
                return response.respondWithError(status: .custom(code: 404,
                    message: "Instance not found or of wrong type"))
            }
            if InstanceController.global.getDeviceUUIDsInInstance(instanceName: name.decodeUrl() ?? "").isEmpty {
                Log.error(message: "[ApiRequestHandler] Instance '\(name)' without devices")
                return response.respondWithError(status: .custom(code: 416, message: "Instance without devices"))
            }
            var size = 0
            if !coords.isEmpty {
                size = instance.addToScanNextCoords(coords: coords)
            }
            do {
                try response.respondWithData(data: [
                    "action": "next_scan",
                    "size": size,
                    "timestamp": Int(Date().timeIntervalSince1970)
                ])
            } catch {
                response.respondWithError(status: .internalServerError)
            }
        } else if clearMemCache {
            Pokemon.cache?.clear()
            Pokestop.cache?.clear()
            Incident.cache?.clear()
            Gym.cache?.clear()
            SpawnPoint.cache?.clear()
            Weather.cache?.clear()
            ImageManager.global.clearCaches()
            response.respondWithOk()
        } else {
            response.respondWithError(status: .badRequest)
        }
    }

}
