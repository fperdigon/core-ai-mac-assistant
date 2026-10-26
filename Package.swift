// swift-tools-version: 6.0
// Copyright 2026 Francisco Perdigon Romero and contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import PackageDescription

let package = Package(
    name: "MacPocketKnife",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MacPocketKnifeCore", targets: ["MacPocketKnifeCore"]),
        .executable(name: "MacPocketKnife", targets: ["MacPocketKnife"]),
    ],
    targets: [
        .target(name: "MacPocketKnifeCore"),
        .executableTarget(
            name: "MacPocketKnife",
            dependencies: ["MacPocketKnifeCore"]
        ),
        .testTarget(
            name: "MacPocketKnifeCoreTests",
            dependencies: ["MacPocketKnifeCore"]
        ),
        .testTarget(
            name: "MacPocketKnifeIntegrationTests",
            dependencies: ["MacPocketKnifeCore"]
        ),
    ]
)
