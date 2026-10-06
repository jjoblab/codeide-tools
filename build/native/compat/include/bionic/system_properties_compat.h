/*
 * Compat bionic pour la compilation autonome des sources AOSP (ADR 0012).
 *
 * __system_property_serial et __system_property_area_serial sont exportées
 * par libc depuis API 19/21 et 23 respectivement (bionic libc.map.txt,
 * vérifié sur android-11.0.0_r1) — donc disponibles sur tout appareil
 * API 30+ — mais les en-têtes NDK curatés ne les déclarent PAS (vérifié
 * jusqu'à API 34). Les sources android-16 les utilisent (libbase, liblog,
 * libcutils/trace-dev.inc…).
 *
 * AUCUNE inclusion ici : ce fichier est force-inclus en TÊTE de toutes les
 * unités C/CXX — une inclusion (p. ex. <sys/system_properties.h>) pourrait
 * tirer <string.h> AVANT le « #undef _GNU_SOURCE » de certains fichiers
 * amont (libbase/posix_strerror_r.cpp), figeant la variante GNU de
 * strerror_r (char*) et cassant leur compilation. D'où : types builtin
 * (__UINT32_TYPE__), prop_info forward-déclaré (le vrai typedef amont
 * « typedef struct prop_info prop_info; » est compatible), extern "C" manuel.
 *
 * DÉCLARATIONS pures : l'édition de liens résout les symboles contre la
 * libc de l'appareil — aucun code substitué.
 */
#pragma once

struct prop_info;

#ifdef __cplusplus
extern "C" {
#endif

__UINT32_TYPE__ __system_property_area_serial(void);

__UINT32_TYPE__ __system_property_serial(const struct prop_info* __pi);

#ifdef __cplusplus
}
#endif
