import AutoConsentCMPBase from './base';

export default class Admiral extends AutoConsentCMPBase {
    name = 'Admiral';

    get hasSelfTest(): boolean {
        return false;
    }

    get isIntermediate(): boolean {
        return false;
    }

    get isCosmetic(): boolean {
        return false;
    }

    async detectCmp() {
        return this.elementExists('div > div[class*=Card] > div[class*=Frame] > div[class*=Pills] > button[class*=Pills__StyledPill]');
    }

    async detectPopup() {
        return this.elementVisible(
            'div > div[class*=Card] > div[class*=Frame] > div[class*=Pills] > button[class*=Pills__StyledPill]',
            'any',
        );
    }

    async optOut() {
        const rejectAllSelector =
            "xpath///button[contains(., 'Afvis alle') or contains(., 'Reject all') or contains(., 'Odbaci sve') or contains(., 'Rechazar todo') or contains(., 'Atmesti visus') or contains(., 'Odmítnout vše') or contains(., 'Απόρριψη όλων') or contains(., 'Rejeitar tudo') or contains(., 'Tümünü reddet') or contains(., 'Отклонить все') or contains(., 'Noraidīt visu') or contains(., 'Avvisa alla') or contains(., 'Odrzuć wszystkie') or contains(., 'Alles afwijzen') or contains(., 'Отхвърляне на всички') or contains(., 'Rifiuta tutto') or contains(., 'Zavrni vse') or contains(., 'Az összes elutasítása') or contains(., 'Respingeți tot') or contains(., 'Alles ablehnen') or contains(., 'Tout rejeter') or contains(., 'Odmietnuť všetko') or contains(., 'Lükka kõik tagasi') or contains(., 'Hylkää kaikki')]";

        if (await this.waitForElement(rejectAllSelector, 500)) {
            return this.click(rejectAllSelector);
        }

        const purposesButtonSelector =
            "xpath///button[contains(., 'Zwecke') or contains(., 'Σκοποί') or contains(., 'Purposes') or contains(., 'Цели') or contains(., 'Eesmärgid') or contains(., 'Tikslai') or contains(., 'Svrhe') or contains(., 'Cele') or contains(., 'Účely') or contains(., 'Finalidades') or contains(., 'Mērķi') or contains(., 'Scopuri') or contains(., 'Fines') or contains(., 'Ändamål') or contains(., 'Finalités') or contains(., 'Doeleinden') or contains(., 'Tarkoitukset') or contains(., 'Scopi') or contains(., 'Amaçlar') or contains(., 'Nameni') or contains(., 'Célok') or contains(., 'Formål')]";

        const saveAndExitSelector =
            "xpath///button[contains(., 'Spara & avsluta') or contains(., 'Save & exit') or contains(., 'Uložit a ukončit') or contains(., 'Enregistrer et quitter') or contains(., 'Speichern & Verlassen') or contains(., 'Tallenna ja poistu') or contains(., 'Išsaugoti ir išeiti') or contains(., 'Opslaan & afsluiten') or contains(., 'Guardar y salir') or contains(., 'Shrani in zapri') or contains(., 'Uložiť a ukončiť') or contains(., 'Kaydet ve çıkış yap') or contains(., 'Сохранить и выйти') or contains(., 'Salvesta ja välju') or contains(., 'Salva ed esci') or contains(., 'Gem & afslut') or contains(., 'Αποθήκευση και έξοδος') or contains(., 'Saglabāt un iziet') or contains(., 'Mentés és kilépés') or contains(., 'Guardar e sair') or contains(., 'Zapisz & zakończ') or contains(., 'Salvare și ieșire') or contains(., 'Spremi i izađi') or contains(., 'Запазване и изход')]";

        if ((await this.waitForThenClick(purposesButtonSelector)) && (await this.waitForVisible(saveAndExitSelector))) {
            const popupBody = this.elementSelector(saveAndExitSelector)[0].parentElement.parentElement;
            const checkboxes = popupBody.querySelectorAll('input[type=checkbox]:checked');
            checkboxes.forEach((checkbox: HTMLElement) => checkbox.click());

            return this.click(saveAndExitSelector);
        }

        return false;
    }

    async optIn() {
        return this.click(
            "xpath///button[contains(., 'Sprejmi vse') or contains(., 'Prihvati sve') or contains(., 'Godkänn alla') or contains(., 'Prijať všetko') or contains(., 'Принять все') or contains(., 'Aceptar todo') or contains(., 'Αποδοχή όλων') or contains(., 'Zaakceptuj wszystkie') or contains(., 'Accetta tutto') or contains(., 'Priimti visus') or contains(., 'Pieņemt visu') or contains(., 'Tümünü kabul et') or contains(., 'Az összes elfogadása') or contains(., 'Accept all') or contains(., 'Приемане на всички') or contains(., 'Accepter alle') or contains(., 'Hyväksy kaikki') or contains(., 'Tout accepter') or contains(., 'Alles accepteren') or contains(., 'Aktsepteeri kõik') or contains(., 'Přijmout vše') or contains(., 'Alles akzeptieren') or contains(., 'Aceitar tudo') or contains(., 'Acceptați tot')]",
        );
    }
}
