.PHONY: project app dmg test open clean

project:  ## Generera Transkribera.xcodeproj
	xcodegen generate

open: project  ## Öppna projektet i Xcode
	open Transkribera.xcodeproj

app:  ## Bygg dist/Transkribera.app
	./scripts/build-app.sh

dmg: app  ## Bygg dist/Transkribera-dev.dmg
	./scripts/make-dmg.sh dev

test:  ## Kör enhetstester för kärnlogiken
	swift test --package-path Packages/TranskriberaCore

clean:
	rm -rf build dist Transkribera.xcodeproj
