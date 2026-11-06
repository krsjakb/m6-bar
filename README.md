# M6 Bar

Natív, magyar macOS menüsáv-alkalmazás a Keychron M6 akkumulátorához.

Az 1.1-es verzió állítható, trackpadszerű görgetésjavítást is tartalmaz.

## Használat

A kész Apple Silicon alkalmazás a [GitHub-kiadásoknál](https://github.com/krsjakb/m6-bar/releases) tölthető le. A ZIP kicsomagolása után az **M6 Bar.app** áthelyezhető az Alkalmazások mappába.

Nyisd meg a **M6 Bar.app** alkalmazást. A menüsávban az egérikon mellett látható a valóban kiolvasott töltöttség. Kattintásra megnyílik a részletes panel. Az appnak nincs állandó Dock ikonja.

- Töltöttség, töltésjelzés, kapcsolat, DPI és lekérdezési frekvencia.
- Automatikus lekérdezés percenként, kézi frissítés a panelen vagy ⌘R-rel.
- Elavult vagy nem elérhető adat esetén a menüsávban „—”; a panelen az utolsó mérés ideje látható.
- 14 nap helyi előzmény, változó töltöttségnél az utolsó 24 óra görbéje.
- A fogaskeréknél bekapcsolható az indulás bejelentkezéskor, megnézhető a firmware, és menthető a diagnosztika.
- Kilépés a panel jobb alsó sarkában.

## Finom görgetés

A **Görgetés** fülön kapcsolható be és hangolható a görgetésjavítás. Alapértelmezés a felhasználó által választott **Kiegyensúlyozott** profil.

- **Sebesség:** a görgő elfordításához tartozó távolság, 0,3–3× között.
- **Simítás:** közvetlenebb vagy lágyabb átmenet az egyes görgőlépések között.
- **Lendület:** a görgetés kifutásának hossza; nullára állítva kikapcsolható.
- **Precíz / Kiegyensúlyozott / Lendületes:** kész kiindulópontok, amelyek tovább hangolhatók.
- Külön függőleges és vízszintes irány, vízszintes simítás és alkalmazáskivételek.
- A **Trackpadszerű viselkedés** natív görgetési és lendületi fázisokat is küld; ezek kezelése alkalmazásonként eltérhet.

Az első bekapcsoláshoz rendszerengedély kell. A **Rendszerengedély…** gomb a megfelelő macOS-beállítást nyitja meg; a hozzáférést a felhasználó engedélyezi az **M6 Bar** számára. A pontos elnevezés macOS-verziótól függően Kisegítő lehetőségek vagy Eszközvezérlés és adathozzáférés lehet. Az app az engedélyt néhány másodpercenként újraellenőrzi, vagy az **Újraellenőrzés** gomb használható.

Helyileg újrafordított, ad hoc aláírású frissítésnél előfordulhat, hogy a rendszer listájában a kapcsoló bekapcsolva marad, de az új build mégsem kap hozzáférést. Ilyenkor az M6 Bar régi bejegyzését a listából el kell távolítani, majd az **Alkalmazások / M6 Bar.app** fájlt újra hozzáadni és engedélyezni. Az app nem módosítja és nem kerüli meg a macOS engedélyeit.

A javítás minden hagyományos, lépcsőzetes egérgörgőre érvényes. A nyilvános macOS-eseményfelület ezen a ponton nem azonosítja az egyes egereket, ezért a funkciót nem csak az M6-ra szűrjük. A folytonos trackpad-/Magic Mouse-jelek, valamint a Shift/Ctrl/Option/Cmd melletti görgetés natív maradnak. Kattintás, módosítóbillentyű, alkalmazásváltás, alvás vagy kikapcsolás megszakítja az aktuális lendületet. A kivételek a görgetést ténylegesen fogadó alkalmazásra vonatkoznak, a háttérablakokat is beleértve.

Az engedély hiánya vagy a görgetőmotor hibája esetén az eredeti macOS-görgetés használható. Az akkumulátorfigyelés rendszerengedély nélkül is működik. Más görgetést módosító app észlelésekor a panel jelzi az esetleges ütközést.

A megvalósítás saját, nyilvános Quartz API-kra épülő kód; nem tartalmaz Mac Mouse Fix-forráskódot. Csak a görgő, az egérgombok lenyomása és a módosítóbillentyűk állapotváltozása kerül az eseményszűrőhöz. Billentyűleütéseket és egérmozgást nem figyel vagy tárol. A beállítások helyben maradnak.

A simított események az eredeti fizikai jel másolatából készülnek, és közvetlenül az eredeti célfolyamathoz kerülnek. Az eredeti natív ablakpozíciót megőrizzük: az esemény globális pozíciójának azonos értékkel való felülírása is érvénytelenítheti az ablakon belüli adatot. Ezt a konkrét M6 valódi jelével, a natív adatok változatlanságát ellenőrizve is teszteltük.

## Üzemidőbecslés

Kezdetben tanuló állapot jelenik meg. Az app csak legalább 6 óra folyamatos megfigyelés, 8 százalékpont csökkenés és elegendő valódi mérés után mutat tartományt. Töltés, kapcsolatvesztés, Mac-alvás, DPI- vagy frekvenciaváltás új mérési szakaszt indít. A becslés hasonló használatot és ébren lévő Macet feltételez; nem méri az egér aktív használatának óráit. Nem a gyári maximális üzemidőt szorozza meg a százalékkal.

## Eszköztámogatás

**Ezen a gépen igazolt:** Keychron M6 `3434:d060`, Link-KM vevő `3434:d029`, 2,4 GHz. A teszteléskor az egér 83%-ot, 1600 DPI-t, 1000 Hz-et és 1.0.3 firmware-t jelentett.

A kód az ugyanezen modellhez tartozó USB vezérlőfelületet is kezeli, és a kábelt részesíti előnyben, ha megjelenik. A kábelre váltást, fizikai kihúzást/visszadugást, töltésváltást és a Mac valódi altatását a fejlesztés során nem hajtottuk végre. Bluetooth és más M6 hardverváltozatok támogatása ebben a kiadásban nincs megvalósítva.

Az akkumulátormodul kizárólag állapotlekérdezéseket küld a célzott gyártói HID-felületen. Nem módosítja a DPI-t, gombokat vagy firmware-t. Az alkalmazásnak nincs saját hálózati forgalma, előfizetése vagy külső függősége. A segítséggomb a hivatalos kézikönyvet nyitja meg a böngészőben.

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

A görgetési tesztek lefedik a távolság megőrzését, a 60/120/144 Hz-es időzítést, irányváltást, két tengely váltakozását, a lendület folytatását és megszakítását, érvénytelen adatokat, beállításokat, eredeti trackpad-jelek átengedését, saját események visszacsatolásának kizárását, alkalmazáskivételeket és tört pixeleket. A szolgáltatás életciklustesztje engedélyhiányt, kikapcsolást, alvást és leállítást ellenőriz globális eseményelfogás nélkül. A görgetési matematika mért sorlefedettsége 97,08%.

A fizikai görgetési érzetet a véglegesen telepített app rendszerengedélyének megadása után az M6 görgőjével kell ellenőrizni; a programozott egységtesztek ezt nem helyettesítik.

Fejlesztői hibaelhárításhoz a `--record-status` indítási kapcsoló az app saját `~/Library/Application Support/M6Bar/runtime-status.json` fájljába írja a működési állapotot. Ez az akkumulátor, a görgetőmotor és az engedély állapotát tartalmazza, képernyőtartalmat és beviteli eseményeket nem. A kapcsoló nélkül ez az állapotrögzítés nem fut.

## Protokollforrások

A kizárólag lekérdező megvalósítás a [hivatalos Keychron Launcher](https://launcher.keychron.com/) aktuális [implementációjának](https://launcher.keychron.com/main.7b33a86947f3bd52.js) és az [M6 pontos eszközleírásának](https://launcher.keychron.com/static/device/875876448/json/v3.json) vizsgálatán alapul. Nem tartalmaz átvett Launcher-kódot vagy grafikai elemet.

- `B5` kimeneti jelentés, `03`: párosított eszközök, a várt M6 online állapotának ellenőrzése.
- `B3` kimeneti jelentés, `06`: alapadatok; `B4` válasz 63 bájtos tartalmának 19. bájtja az akku (`& 0x7F`) és töltés (`& 0x80`).
- `B5` kimeneti jelentés, `02`: eszközazonosítás és firmware; hibája nem érvényteleníti a sikeres akkumérést.
- Az IOHID jelentésazonosító bájtját a feldolgozás leválasztja. A `d060` modell 1000 Hz-es; a Launcher belső „8k” protokollneve nem a termék 8 kHz-es változatát jelenti.
