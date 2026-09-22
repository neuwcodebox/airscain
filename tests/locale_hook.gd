extends GutHookScript
## Keeps text assertions independent from the developer's persisted UI language.

func run() -> void:
	TranslationServer.set_locale(GameLocale.KOREAN)
