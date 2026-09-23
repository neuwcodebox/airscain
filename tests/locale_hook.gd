extends GutHookScript
## Keeps text assertions independent from the developer's persisted UI language,
## and keeps modal phase briefings from pausing simulations unless a test opts in.

func run() -> void:
	TranslationServer.set_locale(GameLocale.KOREAN)
	PlayerSettings.instance().values.briefings = false
