// swift-tools-version: 5.9
import PackageDescription

let package = Package(
	name: "HealthTrendsShared",
	platforms: [
		.iOS(.v17)
	],
	products: [
		.library(
			name: "HealthTrendsShared",
			targets: ["HealthTrendsShared"])
	],
	targets: [
		.target(
			name: "HealthTrendsShared",
			dependencies: []),
		.testTarget(
			name: "HealthTrendsSharedTests",
			dependencies: ["HealthTrendsShared"]),
	]
)
