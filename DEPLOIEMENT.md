# Mise en service des protections serveur InvoicePro

Les changements de l’application routent les lectures et écritures de données par une Supabase Edge Function. Ils ne seront pleinement actifs qu’après le déploiement ci-dessous. L’authentification Supabase reste appelée depuis le navigateur.

## 1. Installer la limite côté base

Dans Supabase **SQL Editor**, exécuter `supabase/invoicepro-rate-limit.sql`. La table de compteurs n’est accessible qu’au rôle serveur. La limite actuelle est de **60 appels de données par minute et par compte authentifié**, appliquée atomiquement par fenêtre de 60 secondes. Les appels d’authentification restent soumis aux protections/rate limits natives Supabase.

## 2. Configurer et déployer la fonction

Depuis la racine du dépôt, avec Supabase CLI connecté au projet:

```text
supabase link --project-ref gchgzqklguxetaswpdwk
supabase functions deploy invoicepro-gateway
```

Dans **Project Settings → Edge Functions → Secrets** (ou le gestionnaire de secrets de fonctions), définir:

- `ALLOWED_ORIGINS` : l’origine exacte du site en production, par exemple `https://facturation.exemple.fr` (sans chemin; plusieurs origines séparées par des virgules).
- Vérifier que les variables système `SUPABASE_URL`, `SUPABASE_ANON_KEY` et `SUPABASE_SERVICE_ROLE_KEY` sont disponibles à la fonction. La clé de service doit rester uniquement dans le coffre de secrets serveur. Ne jamais la mettre dans `supabase-config.js`, HTML ou Git.

Il faut configurer l’origine avant le déploiement ou immédiatement après. La fonction refuse les requêtes de navigateur si la liste est absente ou si l’origine n’y figure pas.

## 3. Clés navigateur

`sb_publishable` (ou l’ancienne clé `anon`) est une clé client publique par conception. Supabase Auth en navigateur en a besoin, et elle reste visible dans les requêtes du navigateur. La déplacer dans un autre fichier, une variable de build ou une page de configuration ne la rendrait pas secrète. La sécurité repose sur les politiques RLS et les claims Auth. Aucune clé `service_role` n’est présente dans le fichier de configuration actuel. Si une vraie clé privilégiée a déjà été publiée dans un dépôt ou un site, la révoquer/faire tourner dans Supabase.

## 4. Contrôles avant ouverture

- Tester l’accès aux documents de son propre compte, l’accès admin et le refus d’accès aux autres comptes.
- Tester `invoicepro-gateway` avec appels répétés : le 61e appel de données dans la même fenêtre par compte doit renvoyer HTTP 429; la fonction vérifie l’identité Supabase avant de compter.
- Vérifier la fonction `invoicepro_collaborator_count` et son exposition aux utilisateurs authentifiés. Le gateway l’appelle avec le jeton de l’utilisateur et ne contourne donc pas les règles par une clé admin.
- Vérifier que les erreurs dans les logs Edge ne contiennent ni adresse e-mail, jeton ni contenu de facture.
- Tester la politique d’origine depuis le vrai domaine. Les appels depuis localhost ne fonctionneront qu’après ajout explicite de cette origine dans `ALLOWED_ORIGINS`.

## 5. Disponibilité et journal des erreurs

Le gateway fournit une réponse de santé à `https://<project-ref>.supabase.co/functions/v1/invoicepro-gateway/health`. Ajouter cette URL ainsi que l’URL du site à un service externe de disponibilité, régler un intervalle raisonnable et configurer les destinataires d’alerte. Le fournisseur d’uptime et ses coordonnées d’alerte ne sont pas connus ni configurables depuis ce dépôt.

Le navigateur conserve localement au plus 30 entrées d’erreurs techniques minimales (horodatage, opération, catégorie), sans données de facture ni identifiants. Elles ne remontent pas au serveur et disparaissent si le stockage local est effacé. Les erreurs serveur sont journalisées dans les logs Supabase avec identifiant de requête, opération et code d’erreur seulement. Pour une collecte centralisée durable, configurer l’export des logs Supabase vers un fournisseur d’observabilité et définir rétention/accès.

## 6. Pages légales

`confidentialite.html` et `conditions.html` sont des trames reliées depuis l’application. Compléter les champs entre crochets (éditeur, contact, conservation, bases légales, transferts, droit applicable, etc.) et obtenir une validation adaptée avant de les présenter comme notices définitives.
