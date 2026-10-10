// D with no column of the "Готово" stage (N/X-Err-Empty, R3-137): say so and
// offer the two ways out — make the column, or give an existing column that
// stage in Settings → Tasks. Esc leaves things as they are.
import QtQuick
import TodoCpp

SmallDialog {
    id: root
    objectName: "done-column-dialog"

    signal pickStageRequested()

    title: I18n.t("done.noColumn.title")
    fact: I18n.t("done.noColumn.fact")

    function create() {
        root.close();
        AppController.addStatus(I18n.t("done.columnName"), "");
        const sts = AppController.statuses;
        AppController.setStatusCategory(sts[sts.length - 1].id, "done");
    }
    onAccepted: root.create()

    // Sheet order: the main button first.
    buttons: [
        PillButton {
            objectName: "done-column-create"
            primary: true
            solid: true
            text: I18n.t("done.noColumn.create")
            onClicked: root.create()
        },
        PillButton {
            objectName: "done-column-pick"
            text: I18n.t("done.noColumn.pick")
            onClicked: { root.close(); root.pickStageRequested(); }
        }
    ]
}
