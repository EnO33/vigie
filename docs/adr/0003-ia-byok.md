# ADR-0003 — IA en BYOK (clé API utilisateur) ou modèle local

- Statut : accepté
- Date : 2026-11-26

## Contexte

Se connecter avec un abonnement grand public (Claude, ChatGPT…) depuis une application tierce
n'est en général pas autorisé par les conditions des fournisseurs. Une clé API, elle, est faite
pour ça, et un modèle local (Ollama) ne fait sortir aucune donnée.

## Décision

Fournisseurs supportés via clé API : Anthropic, OpenAI, Mistral. Plus Ollama en local, sans clé.
Les clés sont stockées dans le trousseau de l'OS via le port `SecretStore`.

## Conséquences

Aucun backend Vigie. L'utilisateur paie son fournisseur à l'usage et voit exactement ce qui part.
