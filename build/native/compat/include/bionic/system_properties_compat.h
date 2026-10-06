/*
 * Compat bionic pour la compilation autonome des sources AOSP (ADR 0012).
 *
 * __system_property_serial et __system_property_area_serial sont exportées
 * par libc depuis API 19/21 et 23 respectivement (bionic libc.map.txt,
 * vérifié sur android-11.0.0_r1 : « introduced=23 », « introduced-arm=19
 * introduced-arm64=21 ») — donc disponibles sur tout appareil API 30+
 * (contrat minAndroidApi du composant) — mais les en-têtes NDK curatés ne
 * les déclarent PAS (aucun niveau d'API, vérifié jusqu'à 34). Les sources
 * android-16 de libbase (properties.cpp) les utilisent : sans déclaration,
 * la compilation croisée échoue.
 *
 * C'est une DÉCLARATION (pas une redéfinition) : l'édition de liens résout
 * les symboles contre la libc de l'appareil, comme pour toute fonction
 * système — aucun code n'est substitué.
 */
#pragma once

#include <sys/system_properties.h>  /* prop_info */

__BEGIN_DECLS

uint32_t __system_property_area_serial(void);

uint32_t __system_property_serial(const prop_info* __pi);

__END_DECLS
