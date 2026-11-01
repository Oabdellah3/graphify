# Cas de test

Trois briefs réalistes, au format lu par `claude plugin eval` (un dossier par cas : `prompt.md`,
`case.yaml`, `graders/`). Ils nécessitent le connecteur Trimble SketchUp dans la session, et chaque
exécution consomme des sauvegardes `save_model` : lancez-les un par un plutôt qu'en parallèle (une
seule session SketchUp par connecteur).

```
claude plugin eval .claude/skills/sketchup-cuisine-sdb --allow-tools Write,Bash
```
