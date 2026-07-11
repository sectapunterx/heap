// SplashScreen: load-smoke against the live singletons, default public knobs,
// the finished() signal contract, and the auto-animation path Main.qml relies
// on (finished fires when the bar completes; never fires with autoAnimate off).
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "SplashScreen"
    when: windowShown
    visible: true
    width: 400
    height: 400

    Item { id: host; anchors.fill: parent }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    // Smoke: instantiates against the live Brand/BrandLogo/AppController
    // singletons; a renamed property or missing type would return null.
    function test_smoke_load() {
        const s = make('import TodoCpp; SplashScreen { }');
        verify(s !== null, "failed to instantiate SplashScreen");
    }

    // Default public knobs. autoAnimate is forced off so the demo animation
    // does not advance progress while we read the defaults.
    function test_default_knobs() {
        const s = make('import TodoCpp; SplashScreen { autoAnimate: false }');
        compare(s.progress, 0.0, "progress starts at 0");
        compare(s.status, "initializing allocator…");
        compare(s.channel, "stable · channel");
        compare(s.autoDuration, 1200);
        // buildInfo is bound to the live AppController version string.
        compare(s.buildInfo, "v" + AppController.appVersion);
    }

    // progress is the primary public knob ("bind to your loader's progress"):
    // writable, and holds what the loader pushes when autoAnimate is off.
    function test_progress_is_externally_drivable() {
        const s = make('import TodoCpp; SplashScreen { autoAnimate: false }');
        s.progress = 0.37;
        compare(s.progress, 0.37);
        s.progress = 1.0;
        compare(s.progress, 1.0);
    }

    // Signal contract: finished() takes no arguments and is emittable.
    function test_finished_signal_contract() {
        const s = make('import TodoCpp; SplashScreen { autoAnimate: false }');
        let fired = 0;
        s.finished.connect(function() { fired++; });
        s.finished();
        compare(fired, 1);
    }

    // Auto-animate path (Main.qml: onFinished: splashFade.start()): the demo
    // NumberAnimation must drive progress to 1 and emit finished() exactly once.
    function test_auto_animate_emits_finished() {
        const s = make('import TodoCpp; SplashScreen { autoDuration: 80 }');
        let fired = 0;
        s.finished.connect(function() { fired++; });
        // Animation-driven, so poll instead of a blind wait.
        tryVerify(function() { return fired === 1; }, 2000,
                  "finished() must fire when the auto animation completes");
        compare(s.progress, 1, "the bar ends full when the animation finishes");
        compare(fired, 1, "finished() fires exactly once per animation run");
    }

    // running: root.autoAnimate is a live binding — flipping the knob on at
    // runtime must start the animation and reach finished().
    function test_auto_animate_toggled_on_at_runtime() {
        const s = make('import TodoCpp; SplashScreen { autoAnimate: false; autoDuration: 80 }');
        let fired = 0;
        s.finished.connect(function() { fired++; });
        s.autoAnimate = true;
        tryVerify(function() { return fired === 1; }, 2000,
                  "enabling autoAnimate at runtime must run the bar to completion");
        compare(s.progress, 1);
    }

    // Reduced-motion contract (Main.qml sets autoAnimate: !Theme.reducedMotion
    // and dismisses via its own Timer): with autoAnimate off the splash must
    // never fire finished() or move the bar on its own.
    function test_no_spontaneous_finish_when_auto_animate_off() {
        const s = make('import TodoCpp; SplashScreen { autoAnimate: false; autoDuration: 50 }');
        let fired = 0;
        s.finished.connect(function() { fired++; });
        // Deliberate minimal wait: gives a wrongly-running 50ms animation ample
        // time to complete, so a regression would be caught here.
        wait(200);
        compare(fired, 0, "finished() must not fire while autoAnimate is false");
        compare(s.progress, 0.0, "progress must not advance while autoAnimate is false");
    }
}
