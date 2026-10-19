"""Module 9b - WHAT TO DO? recommendation engine (Contract section 20).

Rule-based, farmer-friendly, responsible recommendations. Rules are keyed by
disease name (matched loosely) and adjusted by risk level. The output always
carries a disclaimer: AI suggestions do not replace professional advice.

To extend: add entries to DISEASE_RULES. Unknown diseases fall back to
GENERIC_RULES plus risk-level-based monitoring advice.
"""
from typing import Dict, List, Optional

from ..schemas.schemas import (DiseaseResult, RecommendationCategory,
                               RecommendationItem, RecommendationResult,
                               RiskLevel, RiskResult)

Item = RecommendationItem

DISEASE_RULES: Dict[str, Dict[str, List[Item]]] = {
    "early blight": {
        "do_now": [
            Item(title="Inspect the affected leaves",
                 detail="Check lower, older leaves first - Early Blight usually starts there.",
                 urgency="HIGH"),
            Item(title="Remove badly infected leaves",
                 detail="Pick off heavily spotted leaves and destroy them. Do not compost them.",
                 urgency="HIGH"),
        ],
        "manage": [
            Item(title="Apply a suitable fungicide",
                 detail="Use a copper-based or recommended fungicide from your local dealer, "
                       "following the label. Confirm the choice with your agricultural officer.",
                 urgency="MEDIUM"),
            Item(title="Mulch around the plants",
                 detail="Mulching stops fungal spores in the soil from splashing onto leaves during rain.",
                 urgency="MEDIUM"),
        ],
        "prevent": [
            Item(title="Improve air circulation",
                 detail="Space plants properly and remove weeds so leaves dry faster.",
                 urgency="MEDIUM"),
            Item(title="Rotate crops next season",
                 detail="Do not plant tomato or potato in the same spot next season.",
                 urgency="LOW"),
        ],
        "water": [
            Item(title="Water at the base, not the leaves",
                 detail="Use drip or base watering early in the day so leaves stay dry.",
                 urgency="HIGH"),
        ],
    },
    "late blight": {
        "do_now": [
            Item(title="Act immediately - Late Blight spreads fast",
                 detail="Check the whole field today and remove infected plants and leaves.",
                 urgency="CRITICAL"),
        ],
        "manage": [
            Item(title="Apply recommended fungicide urgently",
                 detail="Late Blight can destroy a crop within days in cool, wet weather. "
                       "Consult your agricultural officer for the right product.",
                 urgency="CRITICAL"),
        ],
        "prevent": [
            Item(title="Avoid working in the field when wet",
                 detail="The fungus spreads on wet clothes, tools and hands.",
                 urgency="HIGH"),
        ],
        "water": [
            Item(title="Keep leaves dry",
                 detail="Stop overhead watering until the outbreak is under control.",
                 urgency="HIGH"),
        ],
    },
    "bacterial spot": {
        "do_now": [
            Item(title="Remove infected leaves",
                 detail="Prune spotted leaves with clean tools and dispose of them away from the field.",
                 urgency="HIGH"),
        ],
        "manage": [
            Item(title="Use copper-based spray",
                 detail="Copper bactericides help limit spread. Confirm dosage with your dealer or officer.",
                 urgency="MEDIUM"),
        ],
        "prevent": [
            Item(title="Disinfect tools and hands",
                 detail="Bacteria spread through wounds and wet contact.",
                 urgency="MEDIUM"),
            Item(title="Avoid overhead irrigation",
                 detail="Splashing water spreads the bacteria leaf to leaf.",
                 urgency="MEDIUM"),
        ],
        "water": [
            Item(title="Water early in the morning",
                 detail="This lets leaves dry quickly during the day.",
                 urgency="MEDIUM"),
        ],
    },
}

GENERIC_RULES: Dict[str, List[Item]] = {
    "manage": [
        Item(title="Monitor the crop closely",
             detail="Check leaves every 2-3 days for spreading spots.",
             urgency="MEDIUM"),
    ],
    "prevent": [
        Item(title="Keep the field clean",
             detail="Remove plant waste and weeds around the crop.",
             urgency="LOW"),
    ],
}

MONITOR_BY_LEVEL = {
    RiskLevel.LOW: Item(title="Keep monitoring",
                        detail="Scan a leaf once a week and watch the risk on the dashboard.",
                        urgency="LOW"),
    RiskLevel.MEDIUM: Item(title="Monitor every 2-3 days",
                           detail="Scan again soon - conditions could get worse.",
                           urgency="MEDIUM"),
    RiskLevel.HIGH: Item(title="Monitor daily",
                         detail="Check the crop every day and follow the actions above.",
                         urgency="HIGH"),
}


def build_recommendations(disease: Optional[DiseaseResult],
                          risk: RiskResult) -> RecommendationResult:
    cats = RecommendationCategory()
    key = disease.name.strip().lower() if disease else ""

    if key and key != "healthy" and key in DISEASE_RULES:
        rules = DISEASE_RULES[key]
        cats.do_now = rules.get("do_now", [])
        cats.manage = rules.get("manage", [])
        cats.prevent = rules.get("prevent", [])
        cats.water = rules.get("water", [])
    elif key == "healthy":
        cats.prevent = [Item(title="Keep up good practices",
                             detail="Healthy crop! Maintain spacing, clean field and steady watering.",
                             urgency="LOW")]
    else:
        cats.manage = GENERIC_RULES["manage"]
        cats.prevent = GENERIC_RULES["prevent"]

    cats.monitor = [MONITOR_BY_LEVEL[risk.level]]
    cats.environment = [
        Item(title="Improve airflow" if risk.level != RiskLevel.LOW else "Maintain good airflow",
             detail="Space plants and remove weeds so leaves dry quickly after rain or watering.",
             urgency="HIGH" if risk.level == RiskLevel.HIGH else "LOW"),
    ]
    return RecommendationResult(categories=cats)