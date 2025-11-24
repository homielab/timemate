//  Created by homielab.com

import Foundation

struct RelaxationTips {
    static let all: [String] = [
        "Posture check! You look like a shrimp 🦐",
        "Hydrate or diedrate 💧",
        "Unclench your jaw. Yes, you.",
        "Drop your shoulders from your ears.",
        "Blink. Manually. Now.",
        "Go look at a tree or something 🌳",
        "Your spine called. It wants to be straight.",
        "Inhale tacos 🌮 Exhale negativity.",
        "Error 404: Stress not found.",
        "Rebooting human... Please wait.",
        "Wiggle your toes. Just do it.",
        "Stop frowning. You'll get wrinkles.",
        "Take a sip. Coffee counts... barely ☕️",
        "Look away! The pixels are burning.",
        "Stretch like a cat 🐱",
        "Do a little dance. No one's watching 💃",
        "Think about puppies 🐶",
        "You are not a robot. Take a break.",
        "Earth says hello. Go say hi back.",
        "Close your tabs. Just kidding, close your eyes.",
        "Relax. The work will still be there.",
        "Don't be a workaholic. Be a work-a-frolic.",
        "Give your brain a hug.",
        "Silence is golden. Enjoy it."
    ]
    
    static func random() -> String {
        return all.randomElement() ?? "Relax your eyes..."
    }
}
