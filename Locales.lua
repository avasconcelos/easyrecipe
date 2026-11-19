local _, ns = ...

local L = {
    HEADER = "Recipes using this item",
    NOT_LEARNED = "not learned",
    MORE = "+%d more (hold Shift while hovering)",
    HINT = "open each of your profession windows once so your recipes can be recorded.",
    SCANNED = "%d known recipes recorded.",
    ENABLED = "tooltip lines enabled.",
    DISABLED = "tooltip lines disabled.",
    ALL_ON = "also showing recipes you have not learned.",
    ALL_OFF = "showing only recipes you know.",
    MAX_SET = "showing up to %d recipes per tooltip.",
    MAX_USAGE = "usage: /easyrecipe max <number>",
    RESET = "recipe data cleared. Open your profession windows again to rebuild it.",
    STATUS = "%d known recipes recorded (%d including unlearned).",
    NO_TOOLTIP_API = "this client has no tooltip data API, so tooltips are left untouched.",
    STATUS_LEVELS = "Crafted item recorded for %d recipes, its required level for %d.",
    EXTRA_ERROR = "something could not be set up: %s",
    NO_OPTIONS = "the options panel is not available. Use the /easyrecipe commands instead.",
    OPTIONS_COMBAT = "the options can't be opened in combat. Try again after the fight.",
    OPT_GENERAL = "General",
    OPT_ENABLED = "Show recipes in tooltips",
    OPT_ENABLED_TIP = "List your recipes in the tooltip of the reagents they use.",
    OPT_MINIMAP = "Minimap button",
    OPT_MINIMAP_TIP = "Show the EasyRecipe button around the minimap.",
    OPT_UNLEARNED = "Recipes you have not learned",
    OPT_UNLEARNED_TIP = "Also list, in gray, the recipes of your professions that you have not learned yet.",
    OPT_MAX = "Recipes per tooltip",
    OPT_MAX_TIP = "How many recipes a tooltip lists. Hold Shift while hovering to see up to %d.",
    OPT_DIFFICULTY = "Difficulty",
    OPT_OPTIMAL = "Orange",
    OPT_MEDIUM = "Yellow",
    OPT_EASY = "Green",
    OPT_TRIVIAL = "Gray",
    OPT_DIFFICULTY_TIP = "List the recipes that have this color in your profession window.",
    OPT_LEVEL = "Level of the crafted item",
    OPT_MIN_LEVEL = "Lowest level",
    OPT_MAX_LEVEL = "Highest level",
    OPT_LEVEL_TIP = "A recipe is listed when the level required to use the item it makes is within this range. Recipes for items anyone can use, such as bars and bolts of cloth, and for enchantments are always listed.",
    OPT_PROFESSIONS = "Professions of this character",
    OPT_PROFESSION_TIP = "List the recipes of this profession.",
    MINIMAP_CLICK = "Click to open the options.",
    INTRO_TITLE = "Welcome to EasyRecipe",
    INTRO_TEXT = "1. Open each of your profession windows once, so your recipes can be recorded.\n\n"
        .. "2. Hover a reagent in your bags or bank: the tooltip lists your recipes that use it, by profession.\n\n"
        .. "3. To choose what is listed (difficulty colors, level of the crafted item, professions), "
        .. "click the EasyRecipe button on the minimap or type /easyrecipe config.",
    INTRO_OPTIONS = "Open the options",
    INTRO_OK = "Got it",
    HELP = {
        "/easyrecipe config - open the options",
        "/easyrecipe on | off - enable or disable the tooltip lines",
        "/easyrecipe all - toggle recipes you have not learned",
        "/easyrecipe max <number> - recipes shown per tooltip",
        "/easyrecipe reset - clear this character's recorded recipes",
    },
}

if GetLocale() == "ptBR" then
    L.HEADER = "Receitas que usam este item"
    L.NOT_LEARNED = "não aprendida"
    L.MORE = "+%d receitas (segure Shift ao passar o mouse)"
    L.HINT = "abra a janela de cada profissão uma vez para que suas receitas sejam registradas."
    L.SCANNED = "%d receitas conhecidas registradas."
    L.ENABLED = "linhas no tooltip ativadas."
    L.DISABLED = "linhas no tooltip desativadas."
    L.ALL_ON = "mostrando também receitas que você ainda não aprendeu."
    L.ALL_OFF = "mostrando apenas receitas que você conhece."
    L.MAX_SET = "mostrando até %d receitas por tooltip."
    L.MAX_USAGE = "uso: /easyrecipe max <número>"
    L.RESET = "dados de receitas apagados. Abra suas profissões de novo para refazer o registro."
    L.STATUS = "%d receitas conhecidas registradas (%d contando as não aprendidas)."
    L.NO_TOOLTIP_API = "este cliente não tem a API de dados de tooltip, então os tooltips não são alterados."
    L.STATUS_LEVELS = "Item fabricado registrado em %d receitas, o nível exigido dele em %d."
    L.EXTRA_ERROR = "algo não pôde ser preparado: %s"
    L.NO_OPTIONS = "o painel de opções não está disponível. Use os comandos /easyrecipe."
    L.OPTIONS_COMBAT = "as opções não podem ser abertas em combate. Tente de novo depois da luta."
    L.OPT_GENERAL = "Geral"
    L.OPT_ENABLED = "Mostrar receitas nos tooltips"
    L.OPT_ENABLED_TIP = "Lista suas receitas no tooltip dos reagentes que elas usam."
    L.OPT_MINIMAP = "Botão no minimapa"
    L.OPT_MINIMAP_TIP = "Mostra o botão do EasyRecipe em volta do minimapa."
    L.OPT_UNLEARNED = "Receitas que você não aprendeu"
    L.OPT_UNLEARNED_TIP = "Lista também, em cinza, as receitas das suas profissões que você ainda não aprendeu."
    L.OPT_MAX = "Receitas por tooltip"
    L.OPT_MAX_TIP = "Quantas receitas um tooltip lista. Segure Shift ao passar o mouse para ver até %d."
    L.OPT_DIFFICULTY = "Dificuldade"
    L.OPT_OPTIMAL = "Laranja"
    L.OPT_MEDIUM = "Amarela"
    L.OPT_EASY = "Verde"
    L.OPT_TRIVIAL = "Cinza"
    L.OPT_DIFFICULTY_TIP = "Lista as receitas que têm esta cor na janela da sua profissão."
    L.OPT_LEVEL = "Nível do item fabricado"
    L.OPT_MIN_LEVEL = "Nível mínimo"
    L.OPT_MAX_LEVEL = "Nível máximo"
    L.OPT_LEVEL_TIP = "Uma receita é listada quando o nível exigido para usar o item que ela faz está dentro desta faixa. Receitas de itens que qualquer um pode usar, como barras e peças de tecido, e de encantamentos são sempre listadas."
    L.OPT_PROFESSIONS = "Profissões deste personagem"
    L.OPT_PROFESSION_TIP = "Lista as receitas desta profissão."
    L.MINIMAP_CLICK = "Clique para abrir as opções."
    L.INTRO_TITLE = "Bem-vindo ao EasyRecipe"
    L.INTRO_TEXT = "1. Abra a janela de cada profissão uma vez, para que suas receitas sejam registradas.\n\n"
        .. "2. Passe o mouse sobre um reagente na bolsa ou no banco: o tooltip lista as suas receitas que o usam, por profissão.\n\n"
        .. "3. Para escolher o que é listado (cores de dificuldade, nível do item fabricado, profissões), "
        .. "clique no botão do EasyRecipe no minimapa ou digite /easyrecipe config."
    L.INTRO_OPTIONS = "Abrir as opções"
    L.INTRO_OK = "Entendi"
    L.HELP = {
        "/easyrecipe config - abre as opções",
        "/easyrecipe on | off - ativa ou desativa as linhas no tooltip",
        "/easyrecipe all - alterna as receitas que você ainda não aprendeu",
        "/easyrecipe max <número> - receitas mostradas por tooltip",
        "/easyrecipe reset - apaga as receitas registradas deste personagem",
    }
end

ns.L = L
