-- Chroma Bridge - control.lua
-- Ecrit dans script-output/ :
--   chroma_status.json    -> etat continu (ecrase a chaque tick de polling)
--   chroma_events.jsonl   -> evenements discrets (une ligne JSON ajoutee par evenement)
--   chroma_mapping.json   -> config appareil/touche/couleur/clignotement editee
--                            depuis l'interface en jeu (CONTROL+SHIFT+C), voir gui.lua
--
-- Les fichiers sont dans :
--   %APPDATA%\Factorio\script-output\  (Windows)

local util = require("util")
local gui = require("gui")

local POLL_INTERVAL_TICKS = 60 -- 1x par seconde (60 ticks = 1s a vitesse normale)
local CRAFT_EVENT_MIN_INTERVAL = 30 -- ticks (~0.5s) entre deux "item_crafted" pour eviter le spam

-- Table inversee id -> nom, construite une seule fois, pour retrouver le nom
-- lisible (ex: "no_storage") a partir de l'id renvoye par player.get_alerts().
local ALERT_TYPE_NAMES = {}
for name, id in pairs(defines.alert_type) do
  ALERT_TYPE_NAMES[id] = name
end

local last_craft_event_tick = 0
local POWER_SCAN_RADIUS = 150 -- tuiles autour de chaque joueur connecte (pas toute la base, pour les perfs)

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

-- Compte, pour chaque type d'alerte (defines.alert_type), le nombre d'alertes
-- actives actuellement sur tous les joueurs connectes / toutes les surfaces.
local function count_alerts_by_type()
  local counts = {}
  for _, player in pairs(game.connected_players) do
    local ok, alerts = pcall(function() return player.get_alerts{} end)
    if ok and alerts then
      for _, by_type in pairs(alerts) do
        for alert_type_id, list in pairs(by_type) do
          local name = ALERT_TYPE_NAMES[alert_type_id]
          if name then
            counts[name] = (counts[name] or 0) + #list
          end
        end
      end
    end
  end
  return counts
end

-- Compte, autour de chaque joueur connecte (rayon borne, pas toute la base),
-- les entites du joueur actuellement en sous-alimentation electrique.
-- Pas un alert_type natif de Factorio, donc compte a part et fusionne dans
-- alerts_by_type pour rester utilisable telle quelle par l'editeur d'alertes.
local function count_power_issues()
  local counts = {no_power = 0, low_power = 0}
  for _, player in pairs(game.connected_players) do
    if player.character then
      local entities = player.surface.find_entities_filtered{
        position = player.character.position,
        radius = POWER_SCAN_RADIUS,
        force = "player",
      }
      for _, entity in pairs(entities) do
        local ok, status = pcall(function() return entity.status end)
        if ok then
          if status == defines.entity_status.no_power then
            counts.no_power = counts.no_power + 1
          elseif status == defines.entity_status.low_power then
            counts.low_power = counts.low_power + 1
          end
        end
      end
    end
  end
  return counts
end

-- Etat continu : evolution biters, recherche en cours, alertes par type,
-- vie du joueur, pollution locale, heure du jour.
local function write_status()
  local force = game.forces["player"]
  local alerts_by_type = count_alerts_by_type()
  local power_issues = count_power_issues()
  alerts_by_type.no_power = power_issues.no_power
  alerts_by_type.low_power = power_issues.low_power

  local player_health = nil
  local local_pollution = 0
  local daytime = nil
  for _, player in pairs(game.connected_players) do
    if player.character then
      local character = player.character
      player_health = character.health / character.prototype.get_max_health()
      local_pollution = player.surface.get_pollution(character.position)
      daytime = player.surface.daytime
    end
    break -- un seul joueur de reference (parties solo typiquement)
  end

  local status = {
    tick = game.tick,
    evolution_factor = force.get_evolution_factor(),
    alerts_by_type = alerts_by_type,
    attack_alerts = (alerts_by_type["entity_under_attack"] or 0) + (alerts_by_type["turret_fire"] or 0),
    player_health = player_health,
    local_pollution = local_pollution,
    daytime = daytime,
  }

  if force.current_research then
    status.current_research = force.current_research.name
    status.research_progress = force.research_progress
  end

  util.safe_write_json("chroma_status.json", status, false)
  -- Recree les champs manquants (health_bar, keyboard_idle, ...) sur les
  -- parties commencees avant leur ajout : on_configuration_changed ne se
  -- redeclenche pas juste parce qu'on a modifie les fichiers du mod sans
  -- changer sa version, donc la migration doit pouvoir tourner ici aussi.
  gui.init_defaults()
  gui.ensure_mapping_file()
end

script.on_nth_tick(POLL_INTERVAL_TICKS, function()
  local ok, err = pcall(write_status)
  if not ok then
    log("[chroma-bridge] erreur dans write_status, ignoree : " .. tostring(err))
  end
end)

-- Evenement : recherche terminee
script.on_event(defines.events.on_research_finished, function(event)
  util.safe_write_json("chroma_events.jsonl", {
    type = "research_finished",
    tick = game.tick,
    research = event.research.name,
  }, true)
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
    end
  end
end)

-- Evenement : fusee lancee
script.on_event(defines.events.on_rocket_launched, function(event)
  util.safe_write_json("chroma_events.jsonl", {
    type = "rocket_launched",
    tick = game.tick,
  }, true)
end)

-- Evenement : joueur mort
script.on_event(defines.events.on_player_died, function(event)
  util.safe_write_json("chroma_events.jsonl", {
    type = "player_died",
    tick = game.tick,
  }, true)
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
  end
end)

-- Evenement : objet fabrique (manuellement) -- limite en frequence pour eviter
-- de spammer chroma_events.jsonl lors d'un craft en masse.
script.on_event(defines.events.on_player_crafted_item, function(event)
  if game.tick - last_craft_event_tick < CRAFT_EVENT_MIN_INTERVAL then
    return
  end
  last_craft_event_tick = game.tick
  util.safe_write_json("chroma_events.jsonl", {
    type = "item_crafted",
    tick = game.tick,
    item = event.item_stack and event.item_stack.valid and event.item_stack.name or nil,
  }, true)
end)

-- --- Interface de configuration en jeu (gui.lua) ---

script.on_init(gui.init_defaults)
script.on_configuration_changed(gui.init_defaults)

script.on_event("chroma-bridge-toggle-gui", safe_gui_handler(function(event)
  gui.toggle(game.get_player(event.player_index))
end))

script.on_event(defines.events.on_gui_click, safe_gui_handler(gui.on_click))
script.on_event(defines.events.on_gui_checked_state_changed, safe_gui_handler(gui.on_checked_state_changed))
script.on_event(defines.events.on_gui_selection_state_changed, safe_gui_handler(gui.on_selection_state_changed))
script.on_event(defines.events.on_gui_text_changed, safe_gui_handler(gui.on_text_changed))
script.on_event(defines.events.on_gui_value_changed, safe_gui_handler(gui.on_value_changed))
script.on_event(defines.events.on_gui_closed, safe_gui_handler(gui.on_closed))
