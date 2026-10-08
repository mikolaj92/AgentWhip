# Whip

Bicz nad pulpitem macOS. Bez zwykłego okna i ikony w Docku.

```sh
./build.sh && open Whip.app
```

- Czeka w prawym dolnym rogu obszaru roboczego ekranu.
- Złap go myszą. Szybki ruch (>900 px/s) powoduje trzask i animację.
- Po trzasku wpisuje losową ze 100 angielskich instrukcji do aktywnego pola i naciska Enter. W aplikacjach czatu Enter zwykle wysyła wiadomość; inne pola mogą reagować inaczej.
- Jeden chwyt pozwala na jeden strzał. Wolne przesuwanie nie wysyła tekstu.
- Po puszczeniu powoli wraca do prawego dolnego rogu.
- PPM na biczu → Quit Whip.
- Wymaga zgody: System Settings → Privacy & Security → Accessibility.
- Nie zmienia aktywnej aplikacji. Jeśli aplikacja zmieni się przed wpisaniem, pomija wiadomość.
- Uwaga: tekst trafia w aktualne miejsce kursora; istniejąca treść nie jest czyszczona.

Stałe `crackVelocity` i `returnSpeed` w `main.swift` określają próg strzału i prędkość powrotu.
