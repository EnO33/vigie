---
name: next-issue
description: Liste ce que la factory Vigie peut prendre ensuite — stories prêtes dans l'ordre des dépendances, bloquées et pourquoi, réservées au board — puis passe la première à work-issue. Use for "/next-issue", "quelle est la prochaine issue", "qu'est-ce qui est prêt".
---

# next-issue

1. Candidates : `gh issue list --state open --label type:story --label status:ready --json number,title,labels,body --limit 100`.
2. Ordre, **uniquement depuis l'état GitHub** (labels, epics, sub-issues), jamais de mémoire :
   1. `prio:p0`, puis `p1`, puis `p2` ;
   2. à priorité égale : epics les plus anciens d'abord, leurs sub-issues dans l'ordre listé
      (`gh api repos/{owner}/{repo}/issues/<epic>/sub_issues`).
3. Écarter et lister à part une candidate qui :
   - porte le label `board`, ou nomme un fichier protégé (voir `docs/factory/FACTORY.md`) ;
   - est « Bloquée par » une issue encore ouverte ;
   - a déjà une PR ouverte (`gh pr list --state open --search "<n> in:body"`) ;
   - est trop grosse (plus de ~300 lignes de diff estimées) : proposer `plan-epic`.
4. Sortie : liste prête dans l'ordre, puis bloquées (avec le bloquant), puis écartées (avec la raison).
5. Sauf demande de simple consultation, enchaîner sur `work-issue` avec la première.
