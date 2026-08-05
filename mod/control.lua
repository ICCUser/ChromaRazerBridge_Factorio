-- Chroma Bridge - control.lua
-- Ecrit dans script-output/ :
--   chroma_status.json         -> etat continu, partage pour toute l'equipe
--                                 (ecrase a chaque tick de polling)
--   chroma_events.jsonl        -> evenements discrets PARTAGES (recherche, base
--                                 attaquee, fusee, train a quai -- concernent
--                                 toute l'equipe, pas un joueur en particulier)
--   chroma_player_events.jsonl -> evenements discrets PRIVES a un joueur (ex:
--                                 craft manuel) -- ecrit avec player_index
--                                 cible, n'atterrit que sur sa machine
--   Les deux fichiers d'evenements sont vides en debut de session PUIS
--   periodiquement (voir EVENTS_RESET_INTERVAL_TICKS) pour ne pas grossir
--   sans fin sur une session tres longue -- voir plus bas.
--   chroma_mapping.json        -> config appareil/touche/couleur/clignotement
--                                 editee depuis l'interface en jeu
--                                 (CONTROL+SHIFT+C), voir gui.lua -- privee
--
-- Les fichiers sont dans :
--   %APPDATA%\Factorio\script-output\  (Windows)

local util = require("util")
local gui = require("gui")
local event_explorer = require("event_explorer")

local POLL_INTERVAL_TICKS = 60 -- 1x par seconde (60 ticks = 1s a vitesse normale)
local TRAIN_SCAN_INTERVAL_TICKS = 6 -- ~0.1s : alerte de securite, doit reagir plus vite que le statut general
local POWER_SCAN_INTERVAL_TICKS = 180 -- ~3s : contrairement au train (danger immediat), une coupure de
                                       -- courant n'a pas besoin d'etre detectee a la seconde pres --
                                       -- ce scan reste le plus couteux du mod meme apres filtre de
                                       -- type/rayon (voir POWER_SCAN_RADIUS), l'espacer du reste du
                                       -- statut (POLL_INTERVAL_TICKS) divise d'autant sa contribution
                                       -- totale au temps de frame. Resultat mis en cache
                                       -- (storage.chroma_power_cache) et relu par write_status.
local CRAFT_EVENT_MIN_INTERVAL = 30 -- ticks (~0.5s) entre deux "item_crafted" pour eviter le spam
local MAPPING_SELF_REPAIR_INTERVAL_TICKS = 60 * 15 -- ~15s : gui.ensure_mapping_files() re-ecrit
                                                    -- chroma_mapping.json de chaque joueur, uniquement
                                                    -- pour se reparer si le fichier a disparu -- pas
                                                    -- besoin que ce filet de securite tourne aussi
                                                    -- souvent que le reste du statut, ca ne faisait que
                                                    -- (de)serialiser en JSON et reecrire sur disque pour
                                                    -- rien la quasi-totalite du temps.
local EVENTS_RESET_INTERVAL_TICKS = 60 * 60 * 10 -- ~10 min a vitesse normale : purge periodique de
                                                  -- chroma_events.jsonl (seul fichier en ecriture
                                                  -- "append") pour qu'une session tres longue (8h+,
                                                  -- AFK/craft en masse) ne le fasse pas grossir sans
                                                  -- fin entre deux purges de debut de session

-- Table inversee id -> nom, construite une seule fois, pour retrouver le nom
-- lisible (ex: "no_storage") a partir de l'id renvoye par player.get_alerts().
local ALERT_TYPE_NAMES = {}
for name, id in pairs(defines.alert_type) do
  ALERT_TYPE_NAMES[id] = name
end

local last_craft_event_tick = {} -- par joueur (event.player_index) : le seuil anti-spam
                                   -- (CRAFT_EVENT_MIN_INTERVAL) ne doit s'appliquer qu'a un
                                   -- meme joueur qui craft en rafale, pas empecher le craft
                                   -- d'un autre joueur juste parce que le premier vient d'agir
local POWER_SCAN_RADIUS = 40 -- tuiles autour de chaque joueur connecte (pas toute la base, pour les perfs).
                             -- 150 a l'origine : sur une base dense, le scan ramenait des milliers
                             -- d'entites d'un coup et gelait la frame (~100 ms mesures). Reduit une
                             -- premiere fois a 60 avec un filtre de type, puis encore ici : sur une
                             -- base avec beaucoup de beacons/assembleuses groupees, 60 tuiles peut
                             -- encore ramener beaucoup d'entites -- combine a POWER_SCAN_INTERVAL_TICKS
                             -- (scan moins frequent) plutot que de choisir entre les deux.
local TRAIN_PROXIMITY_RADIUS = 15 -- bien plus serre que POWER_SCAN_RADIUS : "danger immediat", pas "quelque part dans la base"

-- Compteurs par mod pour l'explorateur d'evenements (storage.chroma_mod_counts
-- [event_ou_alerte][nom_du_mod] = nombre de fois vu), partages pour toute
-- l'equipe -- c'est juste de la stat d'exploration, pas une config perso.
local function record_mod_count(key, mod_name)
  if not key then return end
  storage.chroma_mod_counts = storage.chroma_mod_counts or {}
  storage.chroma_mod_counts[key] = storage.chroma_mod_counts[key] or {}
  storage.chroma_mod_counts[key][mod_name] = (storage.chroma_mod_counts[key][mod_name] or 0) + 1
end

-- Compare le message de chaque alerte "custom" (haut-parleur programmable,
-- case "Alerte" + texte libre) au match_text de chaque watch defini par CE
-- joueur (storage.player_mappings[...].custom_alert_watches, voir gui.lua).
-- Alimente alerts_by_type sous la cle "custom_<id>" pour reutiliser tel quel
-- l'editeur d'alertes existant (couleur/device/priorite generiques).
local function count_custom_alert_watches(player, alerts)
  local counts = {}
  local mapping = gui.player_mapping(player)
  local watches = mapping and mapping.custom_alert_watches
  if not watches or #watches == 0 then return counts end
  for _, by_type in pairs(alerts) do
    local list = by_type[defines.alert_type.custom]
    if list then
      for _, alert_data in pairs(list) do
        local ok, text = pcall(tostring, alert_data.message)
        if ok and text and text ~= "" then
          local lowered = text:lower()
          for _, watch in ipairs(watches) do
            if watch.match_text and watch.match_text ~= "" and lowered:find(watch.match_text:lower(), 1, true) then
              local key = "custom_" .. watch.id
              counts[key] = (counts[key] or 0) + 1
            end
          end
        end
      end
    end
  end
  return counts
end

-- Emballe un gestionnaire d'evenement de GUI dans un pcall : une erreur dans
-- l'interface (ex: nom de touche saisi bizarrement) ne doit jamais planter
-- la simulation du jeu, juste s'afficher dans le log.
local function safe_gui_handler(handler)
  return function(event)
    local ok, err = pcall(handler, event)
    if not ok then
      log("[chroma-bridge] erreur GUI ignoree : " .. tostring(err))
    end
  end
end

local function _get_alerts(player)
  return player.get_alerts{}
end

-- Compte, pour UN joueur donne, le nombre d'alertes actives par type
-- (defines.alert_type). L'effet RGB n'a besoin QUE de ce compte par type
-- (#list) : c'est O(nombre de types), pas O(nombre d'alertes).
--
-- ATTENTION PERF : ne PAS reintroduire de boucle "for alert_data in list" ici.
-- Profile sur la base Py d'Ibalek : player.get_alerts{} renvoie ~3381 alertes
-- actives, et boucler dessus pour appeler event_explorer.mod_of (pcall + acces
-- prototype.icon) coutait 38 ms PAR joueur connecte et PAR poll (1x/s) -- soit
-- ~76 ms a deux, la vraie cause des micro-freezes (le scan electrique, lui,
-- ne pesait que 0.16 ms une fois filtre). L'attribution par mod
-- (storage.chroma_mod_counts, purement de la stat d'exploration) reste
-- alimentee par les gestionnaires d'evenements discrets (on_research_finished,
-- on_train_changed_state, ...) ou le volume est faible, pas depuis ce scan
-- periodique.
local function count_player_alerts(player)
  local counts = {}
  local ok, alerts = pcall(_get_alerts, player)
  if ok and alerts then
    for _, by_type in pairs(alerts) do
      for alert_type_id, list in pairs(by_type) do
        local name = ALERT_TYPE_NAMES[alert_type_id]
        if name then
          counts[name] = (counts[name] or 0) + #list
        end
      end
    end
    for key, n in pairs(count_custom_alert_watches(player, alerts)) do
      counts[key] = (counts[key] or 0) + n
    end
  end
  return counts
end

-- Seuls types scannes pour le statut electrique : les consommateurs qui
-- peuvent vraiment passer en no_power/low_power. Sans ce filtre, le scan
-- ramenait TOUTES les entites du rayon (belts, pipes, poteaux, rails...),
-- soit des milliers de resultats inutiles sur une base dense -- c'etait la
-- cause principale du gel d'une frame a chaque poll.
local POWERED_ENTITY_TYPES = {
  "assembling-machine", "furnace", "mining-drill", "inserter", "lab",
  "pump", "beacon", "radar", "roboport",
}

-- Compte, autour d'UN joueur donne (rayon borne, pas toute la base), ses
-- entites actuellement en sous-alimentation electrique. Pas un alert_type
-- natif de Factorio, donc compte a part et fusionne dans alerts_by_type pour
-- rester utilisable telle quelle par l'editeur d'alertes.
local function count_player_power_issues(player)
  local counts = {no_power = 0, low_power = 0}
  if player.character then
    local entities = player.surface.find_entities_filtered{
      position = player.character.position,
      radius = POWER_SCAN_RADIUS,
      type = POWERED_ENTITY_TYPES,
      force = "player",
    }
    -- Plus de pcall par entite : tous les types de POWERED_ENTITY_TYPES
    -- exposent .status (qui peut valoir nil, jamais une erreur), et un pcall
    -- par entite etait un surcout mesurable a l'echelle du scan.
    for _, entity in pairs(entities) do
      local status = entity.status
      if status == defines.entity_status.no_power then
        counts.no_power = counts.no_power + 1
      elseif status == defines.entity_status.low_power then
        counts.low_power = counts.low_power + 1
      end
    end
  end
  return counts
end

-- Types de materiel roulant a considerer : pas seulement les locomotives --
-- un train long peut avoir sa locomotive a plus de TRAIN_PROXIMITY_RADIUS du
-- joueur alors qu'un wagon du meme convoi est juste a cote (danger reel
-- manque si on ne cherche que "locomotive").
local ROLLING_STOCK_TYPES = {"locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon"}

-- Fermeture nommee plutot qu'anonyme recreee a chaque appel : ce scan tourne
-- 10x/seconde et par joueur connecte (TRAIN_SCAN_INTERVAL_TICKS).
local function _find_rolling_stock(player)
  return player.surface.find_entities_filtered{
    position = player.character.position,
    radius = TRAIN_PROXIMITY_RADIUS,
    type = ROLLING_STOCK_TYPES,
    force = "player",
  }
end

-- Alerte de proximite : un train EN MOUVEMENT dans un rayon serre autour du
-- joueur (voir TRAIN_PROXIMITY_RADIUS) -- pense pour prevenir avant de se
-- faire percuter en traversant une voie, pas pour signaler "il y a un train
-- dans le coin". On ignore volontairement notre propre convoi (si le joueur
-- est lui-meme a bord d'un train, .train existe sur son vehicule) : sinon
-- l'alerte resterait allumee en permanence pendant tout trajet en train.
local function count_nearby_moving_train(player)
  local counts = {train_nearby = 0}
  if not player.character then return counts end
  if player.vehicle and player.vehicle.train then return counts end

  local seen_trains = {}
  local ok, rolling_stock = pcall(_find_rolling_stock, player)
  if not ok then return counts end

  for _, car in pairs(rolling_stock) do
    local train = car.valid and car.train
    if train and train.valid and train.speed ~= 0 and not seen_trains[train.id] then
      seen_trains[train.id] = true
      counts.train_nearby = counts.train_nearby + 1
    end
  end
  return counts
end

-- Ecrit train_nearby dans son propre petit fichier, cible sur la machine de
-- CE joueur, a un rythme bien plus rapide (TRAIN_SCAN_INTERVAL_TICKS) que le
-- reste du statut (POLL_INTERVAL_TICKS, 1x/seconde) -- sinon on garde jusqu'a
-- 1s de retard entre le train qui entre dans le rayon et l'alerte qui
-- s'allume, trop lent pour un avertissement de securite. factorio_watcher.py
-- (cote bridge) lit ce fichier en plus de chroma_player_status.json et
-- fusionne sa valeur dans alerts_by_type.
script.on_nth_tick(TRAIN_SCAN_INTERVAL_TICKS, function()
  for _, player in pairs(game.connected_players) do
    local ok, counts = pcall(count_nearby_moving_train, player)
    if ok then
      util.safe_write_json("chroma_train_proximity.json", counts, false, player.index)
    end
  end
end)

-- Scan electrique : le plus couteux du mod (voir POWER_SCAN_RADIUS), donc a
-- part et moins frequent que le reste du statut (POWER_SCAN_INTERVAL_TICKS,
-- ~3s au lieu de 1s). Resultat mis en cache par joueur ; write_status()
-- relit simplement ce cache au lieu de rescanner a chaque appel.
script.on_nth_tick(POWER_SCAN_INTERVAL_TICKS, function()
  storage.chroma_power_cache = storage.chroma_power_cache or {}
  for _, player in pairs(game.connected_players) do
    local ok, counts = pcall(count_player_power_issues, player)
    if ok then
      storage.chroma_power_cache[player.index] = counts
    end
  end
end)

script.on_nth_tick(MAPPING_SELF_REPAIR_INTERVAL_TICKS, function()
  local ok, err = pcall(gui.ensure_mapping_files)
  if not ok then
    log("[chroma-bridge] erreur dans ensure_mapping_files, ignoree : " .. tostring(err))
  end
end)

-- Etat partage (propriete de la FORCE, identique pour toute l'equipe --
-- evolution biters, recherche en cours) : un seul fichier, ecrit sans
-- player_index cible, donc visible chez tout le monde (comme avant).
--
-- Etat individuel (alertes, vie, pollution locale, heure du jour -- propres
-- a CHAQUE joueur) : ecrit avec player_index cible, donc chaque fichier
-- n'atterrit QUE sur la machine du joueur concerne (voir
-- util.safe_write_json et gui.write_mapping_file, meme mecanisme).
local function write_status()
  local force = game.forces["player"]

  local shared_status = {
    tick = game.tick,
    evolution_factor = force.get_evolution_factor(),
  }
  if force.current_research then
    shared_status.current_research = force.current_research.name
    shared_status.research_progress = force.research_progress
  end
  util.safe_write_json("chroma_status.json", shared_status, false)

  local power_cache = storage.chroma_power_cache or {}
  for _, player in pairs(game.connected_players) do
    local alerts_by_type = count_player_alerts(player)
    -- Ni train_nearby ni le statut electrique ne sont recalcules ici : le
    -- scan train (TRAIN_SCAN_INTERVAL_TICKS, plus rapide) ecrit deja son
    -- propre fichier, et le scan electrique (POWER_SCAN_INTERVAL_TICKS,
    -- plus lent -- le plus couteux du mod) alimente power_cache a part.
    local power_issues = power_cache[player.index] or {no_power = 0, low_power = 0}
    alerts_by_type.no_power = power_issues.no_power
    alerts_by_type.low_power = power_issues.low_power

    local player_health = nil
    local local_pollution = 0
    if player.character then
      player_health = player.character.health / player.character.prototype.get_max_health()
      local_pollution = player.surface.get_pollution(player.character.position)
    end

    local player_status = {
      alerts_by_type = alerts_by_type,
      attack_alerts = (alerts_by_type["entity_under_attack"] or 0) + (alerts_by_type["turret_fire"] or 0),
      player_health = player_health,
      local_pollution = local_pollution,
      daytime = player.surface.daytime,
    }
    util.safe_write_json("chroma_player_status.json", player_status, false, player.index)
  end

  -- Recree les champs manquants (health_bar, keyboard_idle, ...) sur les
  -- parties commencees avant leur ajout : on_configuration_changed ne se
  -- redeclenche pas juste parce qu'on a modifie les fichiers du mod sans
  -- changer sa version, donc la migration doit pouvoir tourner ici aussi.
  -- Pas cher (aucun I/O si rien ne manque), contrairement a
  -- gui.ensure_mapping_files() ci-dessous -- reste donc au rythme normal.
  gui.init_defaults()
end

-- Les deux fichiers d'evenements (chroma_events.jsonl partage, et le canal
-- prive chroma_player_events.jsonl de chaque joueur connecte) sont en
-- ecriture "append" : sans purge, ils grossissent indefiniment d'une session
-- a l'autre, et un bridge redemarre en cours de partie relirait tout
-- l'historique depuis le debut (voir factorio_watcher.py cote Python, qui se
-- protege desormais aussi de son cote).
local function reset_events_files()
  util.reset_file("chroma_events.jsonl")
  for _, player in pairs(game.connected_players) do
    util.reset_file("chroma_player_events.jsonl", player.index)
  end
end

-- "session_events_reset" est un upvalue Lua simple (PAS dans storage, qui
-- est sauvegarde avec la partie) : il repart a false a chaque (re)chargement
-- de la partie, donc ce bloc ne s'execute qu'une fois par lancement, au
-- premier tick de poll.
local session_events_reset = false

script.on_nth_tick(POLL_INTERVAL_TICKS, function()
  if not session_events_reset then
    session_events_reset = true
    reset_events_files()
  end
  local ok, err = pcall(write_status)
  if not ok then
    log("[chroma-bridge] erreur dans write_status, ignoree : " .. tostring(err))
  end
end)

-- Purge periodique en plus de celle de debut de session (voir
-- EVENTS_RESET_INTERVAL_TICKS) : sur une session de plusieurs heures, les
-- fichiers ne doivent jamais accumuler plus de ~10 min d'evenements avant
-- d'etre vides. game.tick continue a compter d'une session a l'autre
-- (persiste avec la partie), donc on_nth_tick reste aligne sur des
-- intervalles reguliers de temps de jeu reellement ecoule, independamment
-- du moment ou la partie a ete (re)chargee.
script.on_nth_tick(EVENTS_RESET_INTERVAL_TICKS, reset_events_files)

-- Evenement : recherche terminee
script.on_event(defines.events.on_research_finished, function(event)
  util.safe_write_json("chroma_events.jsonl", {
    type = "research_finished",
    tick = game.tick,
    research = event.research.name,
  }, true)
  record_mod_count("research_finished", event_explorer.mod_of(event.research))
end)

-- Evenement : entite du joueur endommagee (attaque de biters typiquement)
script.on_event(defines.events.on_entity_damaged, function(event)
  if event.entity and event.entity.force and event.entity.force.name == "player" then
    if event.cause and event.cause.type and event.cause.type:find("biter") then
      util.safe_write_json("chroma_events.jsonl", {
        type = "base_under_attack",
        tick = game.tick,
        entity = event.entity.name,
      }, true)
      record_mod_count("base_under_attack", event_explorer.mod_of(event.entity.prototype))
    end
  end
end)

-- Evenement : fusee lancee
script.on_event(defines.events.on_rocket_launched, function(event)
  util.safe_write_json("chroma_events.jsonl", {
    type = "rocket_launched",
    tick = game.tick,
  }, true)
  local silo_or_rocket = event.rocket_silo or event.rocket
  record_mod_count("rocket_launched", event_explorer.mod_of(silo_or_rocket and silo_or_rocket.prototype))
end)

-- Evenement : joueur mort. Volontairement PARTAGE (pas cible sur
-- event.player_index) : savoir qu'un coequipier vient de mourir est une
-- alerte d'equipe utile pour tout le monde, pas seulement pour la victime.
script.on_event(defines.events.on_player_died, function(event)
  util.safe_write_json("chroma_events.jsonl", {
    type = "player_died",
    tick = game.tick,
  }, true)
  record_mod_count("player_died", event_explorer.mod_of(event.cause and event.cause.prototype))
end)

-- Evenement : train arrive a quai
script.on_event(defines.events.on_train_changed_state, function(event)
  local train = event.train
  if train.valid and train.state == defines.train_state.wait_station then
    util.safe_write_json("chroma_events.jsonl", {
      type = "train_arrived",
      tick = game.tick,
      station = train.station and train.station.backer_name or nil,
    }, true)
    record_mod_count("train_arrived", event_explorer.mod_of(train.station and train.station.prototype))
  end
end)

-- Evenement : objet fabrique (manuellement) -- action individuelle, ecrite
-- dans le canal PRIVE du joueur concerne (event.player_index) : sans ca, le
-- craft d'un joueur ferait clignoter le clavier de tous les autres joueurs
-- connectes. Limite en frequence (par joueur -- voir last_craft_event_tick)
-- pour eviter de spammer le fichier lors d'un craft en masse.
script.on_event(defines.events.on_player_crafted_item, function(event)
  local last_tick = last_craft_event_tick[event.player_index] or 0
  if game.tick - last_tick < CRAFT_EVENT_MIN_INTERVAL then
    return
  end
  last_craft_event_tick[event.player_index] = game.tick
  util.safe_write_json("chroma_player_events.jsonl", {
    type = "item_crafted",
    tick = game.tick,
    item = event.item_stack and event.item_stack.valid and event.item_stack.name or nil,
  }, true, event.player_index)
  local stack = event.item_stack
  record_mod_count("item_crafted", event_explorer.mod_of(stack and stack.valid and stack.prototype))
end)

-- --- Interface de configuration en jeu (gui.lua) ---

script.on_init(gui.init_defaults)
script.on_configuration_changed(gui.init_defaults)

script.on_event("chroma-bridge-toggle-gui", safe_gui_handler(function(event)
  gui.toggle(game.get_player(event.player_index))
end))

-- Secours au raccourci CONTROL+SHIFT+C : Factorio permet a n'importe quel
-- mod de rentrer en conflit avec ce raccourci (ou au joueur de le
-- reassigner/desactiver par erreur dans Parametres > Commandes) sans que
-- rien ne le signale clairement en jeu. Une commande console fonctionne
-- toujours, quel que soit l'etat des raccourcis clavier.
commands.add_command("chroma-bridge", "Ouvre/ferme la configuration Chroma Bridge (secours si CONTROL+SHIFT+C ne repond pas)", function(command)
  local player = game.get_player(command.player_index)
  if player then
    local ok, err = pcall(gui.toggle, player)
    if not ok then
      log("[chroma-bridge] erreur GUI ignoree (commande /chroma-bridge) : " .. tostring(err))
    end
  end
end)

script.on_event(defines.events.on_gui_click, safe_gui_handler(gui.on_click))
script.on_event(defines.events.on_gui_checked_state_changed, safe_gui_handler(gui.on_checked_state_changed))
script.on_event(defines.events.on_gui_selection_state_changed, safe_gui_handler(gui.on_selection_state_changed))
script.on_event(defines.events.on_gui_text_changed, safe_gui_handler(gui.on_text_changed))
script.on_event(defines.events.on_gui_value_changed, safe_gui_handler(gui.on_value_changed))
script.on_event(defines.events.on_gui_closed, safe_gui_handler(gui.on_closed))
script.on_event(defines.events.on_gui_selected_tab_changed, safe_gui_handler(gui.on_selected_tab_changed))
