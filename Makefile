.PHONY: project app dmg test check-models update-packages open clean

project:  ## Generera Transkribera.xcodeproj
	xcodegen generate

open: project  ## Öppna projektet i Xcode
	open Transkribera.xcodeproj

app:  ## Bygg dist/Transkribera.app
	./scripts/build-app.sh

dmg: app  ## Bygg dist/Transkribera-dev.dmg
	./scripts/make-dmg.sh dev

test:  ## Kör enhetstester för kärnlogiken, Whisper-förloppet och releaseskripten
	swift test --package-path Packages/TranskriberaCore
	swift test --package-path Packages/TranskriberaWhisper
	python3 -m unittest discover -s scripts

check-models:  ## Kontrollera att alla modeller i väljaren går att ladda ner
	./scripts/check-models.sh

update-packages:  ## Uppdatera de låsta paketversionerna i Package.resolved
	UPDATE_PACKAGES=1 ./scripts/build-app.sh

clean:
	rm -rf build dist Transkribera.xcodeproj
