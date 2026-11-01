# Cas de test

Trois briefs réalistes, au format lu par `claude plugin eval` (un dossier par cas : `prompt.md`,
`case.yaml`, `graders/`). Le cas « salle de bain » attend un script Ruby (SketchUp 2019) ; les deux autres peuvent utiliser le connecteur Trimble SketchUp s'il est présent dans la session, et chaque
exécution consomme des sauvegardes `save_model` : lancez-les un par un plutôt qu'en parallèle (une
seule session SketchUp par connecteur).

```
claude plugin eval .claude/skills/sketchup-cuisine-sdb --allow-tools Write,Bash
```
