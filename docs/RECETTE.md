# Recette JuiceFlow — v0.1.0

Passage en revue fonctionnel complet. Cochez au fil de l'eau ; notez en face
de chaque ❌ ce qui cloche (comportement observé vs attendu).

## 1. Lancement & fenêtre

- [ ] Au premier lancement, l'onboarding s'affiche (3 idées + « C'est parti »), et ne réapparaît plus ensuite
- [ ] L'icône verte à éclair est visible dans le Dock et la barre des menus
- [ ] Fermer la fenêtre (bouton rouge) : l'app disparaît du Dock (pas de point blanc) mais reste dans la barre des menus
- [ ] « Ouvrir JuiceFlow » depuis le popover : la fenêtre revient, l'icône Dock aussi
- [ ] La fenêtre ne se redimensionne jamais toute seule (pas de flicker)

## 2. Bandeau héros

- [ ] Branché : « ≈ X h d'autonomie si débranché » + conso moyenne cohérente
- [ ] Débranché : le titre passe à « X h d'autonomie restante » et reste STABLE (pas de saut 2 h → 8 h)
- [ ] Le flux d'énergie boucle physiquement (chargeur ≈ système ± batterie) et les flèches suivent le sens réel
- [ ] Rebranché : le flux s'inverse en ~3 s
- [ ] Les 4 pastilles (score, santé, température, cycles) affichent des valeurs plausibles
- [ ] Survol du score de session : les pénalités sont détaillées et compréhensibles

## 3. Classement temps réel

- [ ] Badge « précision » turquoise (règle sudoers installée) et valeurs en mW/W
- [ ] WindowServer et le noyau apparaissent dans la liste
- [ ] Les helpers sont regroupés (Arc ×20+, etc.), icônes réelles, glyphes colorés pour les daemons
- [ ] Le classement est calme : les barres glissent, pas de réordonnancement frénétique
- [ ] Lancer une vidéo puis regarder JuiceFlow : le navigateur monte et gagne 🌙
- [ ] Clic sur une ligne → panneau détail : sparkline vivante, répartition par sous-processus, CPU en « cœurs »
- [ ] Coût d'autonomie : « +X min en quittant cette app » avec avant/après cohérent
- [ ] Bouton « Quitter l'app » : ferme l'app visée proprement (équivalent ⌘Q)

## 4. Barre des menus

- [ ] Branché : icône batterie + % · Débranché : le libellé passe aux watts (drain moyen)
- [ ] Popover : jauge compacte, autonomie, top 5 avec badges, valeurs à jour
- [ ] Boutons Ouvrir / Réglages (engrenage) / Quitter fonctionnels

## 5. Historique

- [ ] Onglet Historique : la courbe 24 h se construit (un point par minute)
- [ ] Chips du jour : temps sur batterie et Wh consommés plausibles
- [ ] Top du jour : totaux en mWh/Wh qui grossissent au fil du temps
- [ ] Dès demain : « ±X % vs hier » sur la chip d'énergie
- [ ] Fenêtre fermée 10 min : l'historique n'a pas de trou (flux ralenti, pas coupé)

## 6. Alertes (sur batterie uniquement)

- [ ] Test du tuyau : `build/JuiceFlow.app/Contents/MacOS/JuiceFlow --test-alert` → notification avec boutons Quitter / Ignorer 2 h
- [ ] En conditions réelles (débranché + grosse charge type VM) : notification en ~1 min avec gain d'autonomie chiffré
- [ ] Pas de re-notification de la même app dans les 30 min
- [ ] Réglages : sensibilité et interrupteur d'alertes pris en compte

## 7. Réglages

- [ ] ⌘, (fenêtre ouverte) ou engrenage du popover : la fenêtre Réglages s'ouvre
- [ ] « Lancer à la connexion » : apparaît dans Réglages Système → Général → Ouverture
- [ ] Mode précision : état affiché, « Retirer l'autorisation » supprime la règle et repasse en estimation, réactivation OK

## 8. Sobriété de l'app elle-même

- [ ] Fenêtre ouverte : JuiceFlow ≤ ~100 mW dans son propre classement
- [ ] Fenêtre fermée : JuiceFlow quasi invisible dans `JuiceFlow --pm`

## Diagnostics CLI (pour mémoire)

| Commande | Vérifie |
|---|---|
| `.build/debug/JuiceFlow --dump` | lecture batterie/SMC/autonomie vs `pmset`/`ioreg` |
| `.build/debug/JuiceFlow --top [s]` | classement estimation vs `top -o cpu` |
| `.build/debug/JuiceFlow --pm` | parsing powermetrics + conso de JuiceFlow |
| `sqlite3 ~/Library/Application\ Support/JuiceFlow/history.sqlite ...` | contenu de l'historique |
