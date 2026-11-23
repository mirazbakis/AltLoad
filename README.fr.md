<div align="center">

<img src="docs/assets/logo.svg" width="120" height="120" alt="AltLoad">

# AltLoad

**Installez AltStore, SideStore et LiveContainer depuis votre iPhone, signés avec votre propre identifiant Apple. Pas d'ordinateur, pas de certificat partagé.**

[![Latest release](https://img.shields.io/github/v/release/mirazbakis/AltLoad?label=release)](https://github.com/mirazbakis/AltLoad/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/mirazbakis/AltLoad/total)](https://github.com/mirazbakis/AltLoad/releases)
[![iOS](https://img.shields.io/badge/iOS-18%2B-blue)](#prérequis)
[![Stars](https://img.shields.io/github/stars/mirazbakis/AltLoad)](https://github.com/mirazbakis/AltLoad/stargazers)

[Installer](https://altload.org/) · [Télécharger l'IPA](https://github.com/mirazbakis/AltLoad/releases/latest/download/AltLoad.ipa) · [Ajouter la source](https://altdirect.app/?url=https://raw.githubusercontent.com/mirazbakis/AltLoad/main/source.json) · [Versions](https://github.com/mirazbakis/AltLoad/releases)

[English](README.md) · [简体中文](README.zh-Hans.md) · [Русский](README.ru.md) · Français · [한국어](README.ko.md)

</div>

> [!CAUTION]
> **[altload.org](https://altload.org/) et ce dépôt sont les seules sources officielles.** AltLoad est gratuit et traite le mot de passe de votre identifiant Apple et vos données de jumelage : une copie provenant d'ailleurs pourrait être modifiée pour les voler. Vous en avez déjà utilisé une ? Supprimez-la et changez le mot de passe de votre identifiant Apple sur [account.apple.com](https://account.apple.com).

## Ce qu'il fait

L'installation hors App Store (sideloading) demande en général soit un ordinateur qui signe vos apps et les renouvelle tous les 7 jours, soit un certificat partagé qu'Apple peut révoquer à tout moment. AltLoad fait le travail de l'ordinateur directement sur l'iPhone : il jumelle le téléphone avec lui-même, signe le store avec votre propre identifiant Apple, l'installe, puis agit comme AltServer sur le même appareil afin qu'AltStore puisse se renouveler. Il fonctionne avec un identifiant Apple gratuit, et votre mot de passe n'est transmis qu'à Apple.

| | Avec un ordinateur | Avec un certificat partagé | Avec AltLoad |
| :-- | :-- | :-- | :-- |
| Nécessite un ordinateur | Oui, pour l'installation et chaque renouvellement | Généralement seulement pour la configuration | Non sous iOS 27. Un fichier de jumelage sous iOS 18 à 26 |
| Peut être révoqué sans préavis | Non | Oui, par Apple ou par le propriétaire du certificat | Non. Le certificat vous appartient |
| Renouvellement hebdomadaire | Ordinateur sur le même réseau | Non lié à votre identifiant Apple | Sur l'iPhone |
| JIT | Nécessite un outil sur ordinateur | Ne fait pas partie du certificat | Intégré |
| Coût | L'identifiant Apple gratuit suffit | Fixé par celui qui gère le certificat | Gratuit |

## Prérequis

| iOS | Installation et signature | Jumelage |
| :-- | :-- | :-- |
| **27 et versions ultérieures** | Pris en charge | Sur l'iPhone, sans ordinateur |
| **18 à 26** | Pris en charge | Importer un fichier de jumelage distant créé une fois sur un ordinateur avec [iloader](https://github.com/nab138/iloader) ou [idevice_pair](https://github.com/jkcoxson/idevice_pair) |
| **17 et antérieures** | Non pris en charge | Non pris en charge |

Vous avez aussi besoin de :

- Du [Mode développeur](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) activé
- [LocalDevVPN](https://apps.apple.com/app/id6755608044) depuis l'App Store
- Un identifiant Apple. Avec un identifiant gratuit, les apps durent 7 jours

## Installation

**1. Obtenir AltLoad.** Choisissez une méthode :

| Méthode | Idéal pour | Comment |
| :-- | :-- | :-- |
| **Installation avec identifiant Apple** (recommandée) | Signer avec votre propre identifiant Apple, sans ordinateur et sans profil DNS | Installez trois apps gratuites de l'App Store et suivez les étapes sur [altload.org](https://altload.org/). Voir [altpair/README.md](altpair/README.md) |
| **Installation directe** | La méthode la plus rapide. Utilise un certificat partagé, donc révocable | Ouvrez [altload.org](https://altload.org/) dans Safari, acceptez les Conditions, ajoutez le profil DNS et touchez une installation signée |
| **AltStore ou SideStore** | Vous en utilisez déjà un | [Ajoutez la source](https://altdirect.app/?url=https://raw.githubusercontent.com/mirazbakis/AltLoad/main/source.json) et recevez les mises à jour depuis là |
| **Votre propre outil de signature** | Vous signez vous-même les IPA | Téléchargez `AltLoad.ipa` depuis les [Versions](https://github.com/mirazbakis/AltLoad/releases) |

**2. Jumeler votre iPhone.** Dans AltLoad, ouvrez **Outils › Jumeler**, puis allez dans **Réglages › Confidentialité et sécurité › Mode développeur › Jumeler avec AltLoad** et saisissez le code.

**3. Installer un store.** Activez LocalDevVPN, choisissez un store dans l'onglet **Installer** et connectez-vous.

**4. Installer d'autres apps (facultatif).** Dans le menu **…** de l'onglet Installer, ouvrez **Sources** pour ajouter une source au format AltStore et installer ses apps, ou **Installer un IPA depuis Fichiers…** pour un IPA que vous avez déjà. Voir [Sources](docs/SOURCES.md) (en anglais).

## Fonctionnalités

**Installation et signature**
- **Stores :** AltStore Classic et Beta, SideStore et SideStore + LiveContainer, stable ou nightly. Aussi Husk, UTM, MeloNX et Madeira
- **Vos propres apps :** signez et installez n'importe quelle IPA depuis Fichiers
- **Sources :** ajoutez des sources AltStore et SideStore, parcourez leurs apps, lisez les notes de version, installez d'anciennes versions et voyez quand une mise à jour est disponible
- **Équipe de développement :** choisissez l'équipe qui signe, si votre identifiant Apple appartient à plusieurs équipes
- **Plusieurs identifiants Apple :** enregistrez-en plusieurs et changez lors de la connexion. Chaque app mémorise l'identifiant Apple qui l'a signée
- **Nom du certificat :** choisissez, dans les Réglages, le nom qu'AltLoad donne au certificat de développement qu'il demande
- **Droits :** capacités par app, préréglages pour les émulateurs et les outils réseau, et ce que le dernier profil a réellement accordé

**Jumelage et renouvellement**
- **Jumelage sur l'appareil :** sous iOS 27, jumelez en saisissant un code depuis la Dynamic Island
- **AltServer sur l'appareil :** AltStore trouve AltLoad comme il trouve un ordinateur, et il peut rester actif en arrière-plan
- **AltStore sans AltServer :** AltLoad place le fichier de jumelage de cet iPhone là où AltStore 2.3.1 et versions ultérieures le cherchent, afin qu'AltStore puisse se renouveler seul
- **Renouvellement automatique :** renouvelle les apps avant leur expiration et re-signe en arrière-plan celles qui ont été révoquées, avec LocalDevVPN activé et le mot de passe enregistré
- **Fichiers de jumelage :** placez le fichier de jumelage de cet iPhone dans SideStore, StikDebug et d'autres apps installées hors App Store

**JIT et outils**
- **JIT :** ouvrez les apps avec JIT depuis Outils, Raccourcis, Siri ou l'écran d'accueil. Épinglez celles que vous utilisez, exécutez des scripts et acceptez des demandes depuis des liens
- **Outils supplémentaires :** simulation de position, certificats, App IDs et options d'extensions d'app
- **Journaux :** dans les Réglages, voyez ce qu'AltLoad a fait et copiez un rapport en cas d'échec. Les adresses e-mail sont masquées et les mots de passe ne sont jamais journalisés

**Langues :** anglais, chinois, français, allemand, italien, japonais, coréen, portugais (Brésil), russe et espagnol.

## Dépannage

Quand une opération échoue, ouvrez **Réglages › Journaux** et touchez **Copier**, ou touchez **Copier le journal** sur l'écran d'erreur. Collez-le dans un [ticket](https://github.com/mirazbakis/AltLoad/issues). Les problèmes les plus courants sont ci-dessous ; la liste complète est dans [Dépannage](docs/TROUBLESHOOTING.md) (en anglais).

<details>
<summary><b>« Impossible de se connecter à cet iPhone » ou « Connexion refusée »</b></summary>
<br>

LocalDevVPN doit être connecté, le Mode développeur activé et cet iPhone jumelé dans **Outils › Jumeler**. Autorisez l'accès au réseau local si AltLoad le demande. Désactivez toute autre app VPN ou proxy. Si l'échec persiste, désactivez puis réactivez LocalDevVPN, ou jumelez à nouveau.
</details>

<details>
<summary><b>« Couldn't open a tunnel to this device »</b></summary>
<br>

Le service de jumelage a répondu, mais la connexion suivante s'est bloquée. Désactivez puis réactivez LocalDevVPN, attendez quelques secondes et réessayez. Depuis AltLoad 1.8.0, une seule connexion est établie à la fois, donc une installation et l'onglet JIT ne se bloquent plus mutuellement.
</details>

<details>
<summary><b>La connexion échoue</b></summary>
<br>

Laissez **Réglages › Anisette** sur **Automatique**. Si la connexion échoue toujours, touchez **Réinitialiser les données Anisette** et réessayez quelques minutes plus tard. Si AltLoad indique que les connexions sont suspendues, attendez le délai affiché.
</details>

<details>
<summary><b>« Pas assez d'App IDs disponibles »</b></summary>
<br>

Un identifiant Apple gratuit peut créer 10 App IDs par semaine, et chaque extension d'app en nécessite normalement un. Avant d'installer, réglez **Extensions d'app** sur **Conserver, utiliser le profil principal** ou **Supprimer les extensions**.
</details>

<details>
<summary><b>« Limite de certificats atteinte »</b></summary>
<br>

Les identifiants Apple gratuits n'obtiennent que quelques certificats de développement. AltLoad vous demande lequel révoquer. Les apps signées avec celui-ci ailleurs cessent de s'ouvrir jusqu'à ce qu'elles soient à nouveau signées.
</details>

<details>
<summary><b>Un store ne se télécharge pas</b></summary>
<br>

Si toutes les sources d'un store sont indisponibles, obtenez son IPA autrement et utilisez **Installer une IPA depuis Fichiers** dans le menu **…** de l'onglet Installer.
</details>

## Documentation

Les guides sont en anglais.

| Guide | Contenu |
| :-- | :-- |
| [FAQ](docs/FAQ.md) | Mots de passe, limites, révocation, et différences avec AltStore et SideStore |
| [Sources](docs/SOURCES.md) | Ajouter des sources, les mises à jour et les champs qu'AltLoad lit |
| [Dépannage](docs/TROUBLESHOOTING.md) | Les erreurs et que faire |
| [Fonctionnement](docs/HOW-IT-WORKS.md) | Jumelage, tunnel, signature et installation, étape par étape |
| [altpair](altpair/README.md) | Installer AltLoad avec votre identifiant Apple, sans ordinateur |
| [Contribuer](CONTRIBUTING.md) | Compilation, organisation du projet et pull requests |

## Compilation

Il vous faut Xcode, Rust avec les cibles `aarch64-apple-ios` et `aarch64-apple-ios-sim`, et XcodeGen.

```sh
make test   # Tests Rust pour le cœur et altpair
make ipa    # build/AltLoad.ipa, signé ad hoc comme les versions publiées
make sim    # un build pour le Simulator
```

Lisez [Contribuer](CONTRIBUTING.md) avant d'ouvrir une pull request.

| Chemin | Contenu |
| :-- | :-- |
| `ios/` | L'app SwiftUI, l'extension Live Activity et les traductions |
| `core/` | Le cœur Rust pour le jumelage, le tunnel vers l'appareil, la connexion, la signature et l'installation |
| `altpair/` | Les outils propres à AltLoad qui l'installent avec votre identifiant Apple, sans ordinateur. Voir son [README](altpair/README.md) |
| `site/` | La page d'installation sur GitHub Pages |
| `signing/` | Scripts et packs de certificats pour les installations signées |
| `docs/` | Guides, [Fonctionnement](docs/HOW-IT-WORKS.md) et notes de version |

## Licence

AltLoad est open source sous une licence personnalisée basée sur MIT. Vous pouvez lire son code, le modifier, le compiler pour vous-même et réutiliser des parties dans des projets non commerciaux, avec la mention *"Based on AltLoad by mirazbakis"*. Les versions ne peuvent être distribuées que via ce dépôt et le site officiel. Voir [LICENSE.md](LICENSE.md).

Signalez les problèmes de sécurité comme décrit dans [SECURITY.md](SECURITY.md). Utiliser AltLoad implique d'accepter les [Conditions d'utilisation](https://altload.org/terms.html). AltLoad n'est affilié ni à Apple ni à aucune app qu'il installe.

Voir [ACKNOWLEDGMENTS.md](ACKNOWLEDGMENTS.md) pour les projets dont AltLoad dépend, et [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) pour les licences.
