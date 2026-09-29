import Foundation

enum RecommendationMath {
    static func softmaxInverse(scores: [DyslexiaType: Double], temperature: Double) -> [DyslexiaType: Double] {
        let safeTemperature = max(temperature, 0.0001)
        let transformed = scores.mapValues { value in
            -value / safeTemperature
        }
        let maxValue = transformed.values.max() ?? 0
        let exps = transformed.mapValues { value in
            exp(value - maxValue)
        }
        let normalizer = exps.values.reduce(0, +)

        guard normalizer > 0 else {
            let uniform = 1.0 / Double(max(scores.count, 1))
            return Dictionary(uniqueKeysWithValues: scores.keys.map { key in
                (key, uniform)
            })
        }

        return exps.mapValues { value in
            value / normalizer
        }
    }

    static func normalize(_ value: Double, min: Double, max: Double) -> Double {
        guard max > min else { return 0 }
        return (value - min) / (max - min)
    }

    static func bounded(_ value: Double, min: Double = 0.0, max: Double = 1.0) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}
