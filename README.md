# M6 Bar

Natív, magyar macOS menüsáv-alkalmazás a Keychron M6 akkumulátorához.

## Használat

A kész Apple Silicon alkalmazás a [GitHub-kiadásoknál](https://github.com/krsjakb/m6-bar/releases) tölthető le. A ZIP kicsomagolása után az **M6 Bar.app** áthelyezhető az Alkalmazások mappába.

Nyisd meg a **M6 Bar.app** alkalmazást. A menüsávban az egérikon mellett látható a valóban kiolvasott töltöttség. Kattintásra megnyílik a részletes panel. Az appnak nincs állandó Dock ikonja.

- Töltöttség, töltésjelzés, kapcsolat, DPI és lekérdezési frekvencia.
- Automatikus lekérdezés percenként, kézi frissítés a panelen vagy ⌘R-rel.
- Elavult vagy nem elérhető adat esetén a menüsávban „—”; a panelen az utolsó mérés ideje látható.
- 14 nap helyi előzmény, változó töltöttségnél az utolsó 24 óra görbéje.
- A fogaskeréknél bekapcsolható az indulás bejelentkezéskor, megnézhető a firmware, és menthető a diagnosztika.
- Kilépés a panel jobb alsó sarkában.

## Üzemidőbecslés

Kezdetben tanuló állapot jelenik meg. Az app csak legalább 6 óra folyamatos megfigyelés, 8 százalékpont csökkenés és elegendő valódi mérés után mutat tartományt. Töltés, kapcsolatvesztés, Mac-alvás, DPI- vagy frekvenciaváltás új mérési szakaszt indít. A becslés hasonló használatot és ébren lévő Macet feltételez; nem méri az egér aktív használatának óráit. Nem a gyári maximális üzemidőt szorozza meg a százalékkal.

## Eszköztámogatás

**Ezen a gépen igazolt:** Keychron M6 `3434:d060`, Link-KM vevő `3434:d029`, 2,4 GHz. A teszteléskor az egér 83%-ot, 1600 DPI-t, 1000 Hz-et és 1.0.3 firmware-t jelentett.

A kód az ugyanezen modellhez tartozó USB vezérlőfelületet is kezeli, és a kábelt részesíti előnyben, ha megjelenik. A kábelre váltást, fizikai kihúzást/visszadugást, töltésváltást és a Mac valódi altatását a fejlesztés során nem hajtottuk végre. Bluetooth és más M6 hardverváltozatok támogatása ebben a kiadásban nincs megvalósítva.

Az alkalmazás kizárólag állapotlekérdezéseket küld. Nem módosítja a DPI-t, gombokat vagy firmware-t. A célzott gyártói HID-felületet használja, nem figyeli a billentyűleütéseket vagy az egérmozgást. Nincs saját hálózati forgalma, előfizetése vagy külső függősége. A segítséggomb a hivatalos kézikönyvet nyitja meg a böngészőben.

Az előzményfájl: `~/Library/Application Support/M6Bar/history-v1.json`. A törléséhez előbb lépj ki az appból. Az automatikus indulás alapértelmezésben ki van kapcsolva.

## Fordítás és tesztelés

Apple Silicon vagy Intel Mac, macOS 14+, Swift 6-os parancssori fejlesztőeszközök szükségesek. A kész kiadás ezen az Apple Silicon Macen készült és lett kipróbálva.

```sh
./test.sh
./build.sh
```

A fordító a projekt mellett készíti el az `M6 Bar.app` csomagot, helyi ad hoc aláírással. A fordításhoz nincs szükség teljes Xcode-ra vagy csomagletöltésre.

Élő, csak olvasó hardverellenőrzés:

```sh
"../M6 Bar.app/Contents/MacOS/M6Bar" --diagnose
```

A tesztek a valóban rögzített hardverválaszt, az érvénytelen/rövid üzenetek elutasítását, a párosított egér állapotát, a firmware-azonosítást és a becslés feltételeit ellenőrzik. A diagnosztikai futás hat másodpercig tart.

## Protokollforrások

A kizárólag lekérdező megvalósítás a [hivatalos Keychron Launcher](https://launcher.keychron.com/) aktuális [implementációjának](https://launcher.keychron.com/main.7b33a86947f3bd52.js) és az [M6 pontos eszközleírásának](https://launcher.keychron.com/static/device/875876448/json/v3.json) vizsgálatán alapul. Nem tartalmaz átvett Launcher-kódot vagy grafikai elemet.

- `B5` kimeneti jelentés, `03`: párosított eszközök, a várt M6 online állapotának ellenőrzése.
- `B3` kimeneti jelentés, `06`: alapadatok; `B4` válasz 63 bájtos tartalmának 19. bájtja az akku (`& 0x7F`) és töltés (`& 0x80`).
- `B5` kimeneti jelentés, `02`: eszközazonosítás és firmware; hibája nem érvényteleníti a sikeres akkumérést.
- Az IOHID jelentésazonosító bájtját a feldolgozás leválasztja. A `d060` modell 1000 Hz-es; a Launcher belső „8k” protokollneve nem a termék 8 kHz-es változatát jelenti.
