#
# Copyright © 2022 Github Lzhiyong
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Port android-16.0.0_r1 (ADR 0012) : l'amont a réorganisé libprocessgroup —
# cgrouprc_format/ et les anciens noms ont disparu ; sched_policy.cpp et
# task_profiles.cpp ne sont plus dans ce répertoire. Seuls les fichiers
# EXISTANTS sont listés (échec net sinon — pas de repli silencieux).
add_library(libprocessgroup STATIC
    ${SRC}/core/libprocessgroup/cgroup_map.cpp
    ${SRC}/core/libprocessgroup/processgroup.cpp
    ${SRC}/core/libprocessgroup/cgrouprc/a_cgroup_controller.cpp
    ${SRC}/core/libprocessgroup/cgrouprc/a_cgroup_file.cpp
    )

target_include_directories(libprocessgroup PRIVATE
    ${SRC}/core/libprocessgroup/include
    ${SRC}/core/libprocessgroup/cgrouprc/include
    ${SRC}/libbase/include
    ${SRC}/core/libcutils/include
    ${SRC}/jsoncpp/include
    )
target_include_directories(libprocessgroup PRIVATE
    ${SRC}/core/libprocessgroup
    )