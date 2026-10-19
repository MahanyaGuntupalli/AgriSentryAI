/// Agronomy knowledge base (Master Prompt sections 2, 3, 10, 13).
///
/// Data-driven, expandable: adding a new crop or disease means adding an
/// entry here - no screen or service restructuring required.
///
/// All English text stored here is translated on-device through
/// services/translations.dart (tr / trDisease), keeping EN/HI/TE complete.
library;

/// Supported crops. Order matters - it drives the crop picker UI.
enum CropType {
  tomato,
  rice,
  cotton,
  chilli,
  maize;

  /// Canonical lowercase id used in API calls and stored records.
  String get id => name;

  /// Display name - fed through tr() so translations stay centralized.
  String get displayName => switch (this) {
        CropType.tomato => 'Tomato',
        CropType.rice => 'Rice',
        CropType.cotton => 'Cotton',
        CropType.chilli => 'Chilli',
        CropType.maize => 'Maize',
      };

  /// Parses a stored crop id. Returns null when the value is unknown or
  /// blank - callers must show an explicit "not selected" state instead of
  /// silently assuming tomato (data-integrity audit).
  static CropType? tryParse(String? value) {
    final v = (value ?? '').toLowerCase().trim();
    for (final c in CropType.values) {
      if (c.id == v) return c;
    }
    return null;
  }
}

/// How a disease responds to environment - drives the on-device fusion engine.
class FavorableConditions {
  /// Relative humidity (%) above which the disease progresses quickly.
  final double humidityHigh;

  /// Optimal temperature band (°C) for the pathogen.
  final double tempMin, tempMax;

  /// True when free water on leaves (rain, overhead irrigation, dew)
  /// is a major infection trigger.
  final bool needsLeafWetness;

  /// True when waterlogged / very wet soil raises risk (e.g. root rots).
  final bool favorsWetSoil;

  const FavorableConditions({
    required this.humidityHigh,
    required this.tempMin,
    required this.tempMax,
    this.needsLeafWetness = true,
    this.favorsWetSoil = false,
  });
}

/// A known disease for a crop, with farmer-facing facts.
///
/// `name` values intentionally match the backend/PlantVillage class names
/// (e.g. 'Early Blight') so real model outputs map straight onto entries.
class DiseaseKnowledge {
  /// Stable English name. Also used as the trDisease() lookup key.
  final String name;

  final CropType crop;

  /// One-line "what the farmer sees".
  final String symptoms;

  /// Environmental conditions that favor this disease.
  final FavorableConditions favorable;

  /// Which future-risk horizon the pathogen tends to dominate (48h for fast
  /// movers like Late Blight, 72h for slower leaf spots).
  final int typicalSpreadHours;

  /// Practical "do now" actions (prioritized, no unverified chemicals).
  final List<(String title, String detail)> doNow;

  /// Preventive precautions.
  final List<(String title, String detail)> prevent;

  /// What the farmer should watch (drives the Monitor section).
  final List<String> monitorItems;

  /// Practical re-check interval label, e.g. '2-3 days'.
  final String recheckAfterDays;

  const DiseaseKnowledge({
    required this.name,
    required this.crop,
    required this.symptoms,
    required this.favorable,
    this.typicalSpreadHours = 48,
    required this.doNow,
    required this.prevent,
    required this.monitorItems,
    this.recheckAfterDays = '2-3 days',
  });
}

/// "Healthy" is shared by every crop - one entry, mapped to all crops.
const _healthy = DiseaseKnowledge(
  name: 'Healthy',
  crop: CropType.tomato, // ignored - exposed per-crop via healthyFor()
  symptoms: 'The leaf looks green and uniform with no spots or discoloration.',
  favorable: FavorableConditions(
      humidityHigh: 101, tempMin: -50, tempMax: 60, needsLeafWetness: false),
  doNow: [
    ('Keep up good practices',
        'Maintain steady watering, spacing and clean field conditions.'),
  ],
  prevent: [
    ('Regular monitoring',
        'Scan a leaf weekly and watch the risk on the dashboard.'),
  ],
  monitorItems: ['New spots or discoloration', 'Humidity', 'Soil moisture'],
  recheckAfterDays: '7 days',
);

DiseaseKnowledge _healthyFor(CropType c) =>
    DiseaseKnowledge(
      name: 'Healthy',
      crop: c,
      symptoms: _healthy.symptoms,
      favorable: _healthy.favorable,
      doNow: _healthy.doNow,
      prevent: _healthy.prevent,
      monitorItems: _healthy.monitorItems,
      recheckAfterDays: _healthy.recheckAfterDays,
    );

/// The knowledge base. Add new crops/diseases by extending these lists.
const List<DiseaseKnowledge> kDiseaseKnowledge = [
  // ---------------- TOMATO ----------------
  DiseaseKnowledge(
    name: 'Early Blight',
    crop: CropType.tomato,
    symptoms:
        'Dark brown spots with concentric rings, usually starting on lower, older leaves with yellowing around them.',
    favorable: FavorableConditions(
        humidityHigh: 80, tempMin: 20, tempMax: 30, favorsWetSoil: true),
    typicalSpreadHours: 48,
    doNow: [
      ('Inspect the affected leaves',
          'Check lower, older leaves first - Early Blight usually starts there.'),
      ('Remove badly infected leaves',
          'Pick off heavily spotted leaves and destroy them. Do not compost them.'),
      ('Mulch around the plants',
          'Mulching stops fungal spores in the soil from splashing onto leaves during rain.'),
    ],
    prevent: [
      ('Water at the base, not the leaves',
          'Use drip or base watering early in the day so leaves stay dry.'),
      ('Rotate crops next season',
          'Do not plant tomato or potato in the same spot next season.'),
    ],
    monitorItems: [
      'Spread of spots to upper leaves',
      'Humidity',
      'Soil moisture',
    ],
    recheckAfterDays: '2-3 days',
  ),
  DiseaseKnowledge(
    name: 'Late Blight',
    crop: CropType.tomato,
    symptoms:
        'Greasy, water-soaked patches with white fuzzy growth under the leaf; spreads extremely fast in cool wet weather.',
    favorable: FavorableConditions(
        humidityHigh: 85, tempMin: 10, tempMax: 24, needsLeafWetness: true),
    typicalSpreadHours: 24,
    doNow: [
      ('Act immediately - Late Blight spreads fast',
          'Check the whole field today and remove infected plants and leaves.'),
      ('Apply a suitable fungicide',
          'Use a copper-based or recommended fungicide, following the label. Confirm with your agricultural officer.'),
    ],
    prevent: [
      ('Keep leaves dry',
          'Avoid overhead watering until the outbreak is under control.'),
      ('Disinfect tools and hands',
          'The fungus spreads on wet clothes, tools and hands.'),
    ],
    monitorItems: [
      'New water-soaked patches',
      'Rainfall',
      'Temperature and humidity',
    ],
    recheckAfterDays: '1 day',
  ),
  DiseaseKnowledge(
    name: 'Bacterial Spot',
    crop: CropType.tomato,
    symptoms:
        'Small, dark, angular water-soaked spots that may look greasy; leaves can turn yellow and drop.',
    favorable: FavorableConditions(
        humidityHigh: 80, tempMin: 24, tempMax: 32, needsLeafWetness: true),
    typicalSpreadHours: 48,
    doNow: [
      ('Remove infected leaves',
          'Prune spotted leaves with clean tools and dispose of them away from the field.'),
      ('Apply a suitable bactericide',
          'Copper bactericides help limit spread. Confirm dosage with your dealer or officer.'),
    ],
    prevent: [
      ('Avoid overhead irrigation',
          'Splashing water spreads the bacteria leaf to leaf.'),
      ('Disinfect tools and hands',
          'Bacteria spread through wounds and wet contact.'),
    ],
    monitorItems: ['New spots on young leaves', 'Leaf wetness', 'Humidity'],
    recheckAfterDays: '2-3 days',
  ),
  DiseaseKnowledge(
    name: 'Leaf Mold',
    crop: CropType.tomato,
    symptoms:
        'Pale yellowish spots on the upper leaf surface with olive-green fuzzy mold underneath, in humid still air.',
    favorable: FavorableConditions(
        humidityHigh: 85, tempMin: 18, tempMax: 27, needsLeafWetness: false),
    typicalSpreadHours: 48,
    doNow: [
      ('Improve airflow in the canopy',
          'Open up dense foliage and improve ventilation - Leaf Mold thrives in still, humid air.'),
      ('Remove heavily affected leaves',
          'Remove and destroy moldy leaves. Do not leave them in the field.'),
    ],
    prevent: [
      ('Reduce humidity inside the crop',
          'Proper plant spacing and morning watering keep leaves and air drier.'),
      ('Ensure ventilation',
          'Greenhouses and polytunnels need vents opened when humidity rises.'),
    ],
    monitorItems: ['Under-leaf mold growth', 'Humidity', 'Air movement'],
    recheckAfterDays: '2-3 days',
  ),
  DiseaseKnowledge(
    name: 'Septoria Leaf Spot',
    crop: CropType.tomato,
    symptoms:
        'Many small circular spots with dark borders and tiny black dots (fruiting bodies) in the center, on lower leaves first.',
    favorable: FavorableConditions(
        humidityHigh: 80, tempMin: 20, tempMax: 25, needsLeafWetness: true),
    typicalSpreadHours: 48,
    doNow: [
      ('Remove infected lower leaves',
          'Remove spotted lower leaves with clean tools and destroy them away from the field.'),
      ('Mulch around the plants',
          'Mulch blocks spores splashing from soil onto leaves during rain or watering.'),
    ],
    prevent: [
      ('Water at the base, not the leaves',
          'Wet leaves spread Septoria - use drip or base watering.'),
      ('Improve air circulation',
          'Space plants properly and remove weeds so leaves dry faster.'),
    ],
    monitorItems: ['Number of new spots', 'Rainfall', 'Leaf wetness'],
    recheckAfterDays: '2-3 days',
  ),

  // ---------------- RICE ----------------
  DiseaseKnowledge(
    name: 'Rice Blast',
    crop: CropType.rice,
    symptoms:
        'Diamond-shaped spots with grey centers and brown edges on leaves; nodes or panicles may turn brown and break.',
    favorable: FavorableConditions(
        humidityHigh: 85, tempMin: 20, tempMax: 28, needsLeafWetness: true),
    typicalSpreadHours: 48,
    doNow: [
      ('Inspect the field edges',
          'Blast usually starts in shaded, humid corners - check them first.'),
      ('Manage water carefully',
          'Keep the field from drying out completely; stressed rice is more prone to blast.'),
    ],
    prevent: [
      ('Avoid excess nitrogen fertilizer',
          'Heavy nitrogen makes soft, dense growth that blast attacks easily.'),
      ('Ensure good field ventilation',
          'Wider spacing between seedlings reduces humid, still air.'),
    ],
    monitorItems: ['New diamond-shaped spots', 'Humidity', 'Leaf wetness'],
    recheckAfterDays: '2-3 days',
  ),
  DiseaseKnowledge(
    name: 'Rice Leaf Blight',
    crop: CropType.rice,
    symptoms:
        'Wavy-edged yellow to straw-colored lesions running along leaf margins or veins, often after heavy rain or wind.',
    favorable: FavorableConditions(
        humidityHigh: 85, tempMin: 25, tempMax: 34, needsLeafWetness: true),
    typicalSpreadHours: 48,
    doNow: [
      ('Drain standing water briefly',
          'Bacterial leaf blight spreads fast in warm, wet fields - a short drain can slow it.'),
      ('Remove visibly infected plants',
          'Uproot badly affected plants to limit spread through the water.'),
    ],
    prevent: [
      ('Avoid wounding plants',
          'Bacteria enter through cuts from tools, insects or wind damage.'),
      ('Balanced fertilization',
          'Excess nitrogen favors bacterial blight development.'),
    ],
    monitorItems: ['Yellowing leaf margins', 'Rainfall', 'Field water level'],
    recheckAfterDays: '2-3 days',
  ),

  // ---------------- COTTON ----------------
  DiseaseKnowledge(
    name: 'Cotton Leaf Curl',
    crop: CropType.cotton,
    symptoms:
        'Upward or downward curling of leaves with thickened veins; leaves look small, leathery and dark.',
    favorable: FavorableConditions(
        humidityHigh: 60, tempMin: 25, tempMax: 35, needsLeafWetness: false),
    typicalSpreadHours: 72,
    doNow: [
      ('Check for whitefly',
          'Leaf curl is spread by whiteflies - inspect the underside of leaves.'),
      ('Remove and destroy badly curled plants',
          'Remove infected plants so whiteflies cannot spread the virus onward.'),
    ],
    prevent: [
      ('Control whitefly pressure',
          'Yellow sticky traps and clean field edges reduce whitefly numbers. Confirm treatments locally.'),
      ('Remove volunteer hosts',
          'Old crop residue and weeds harbor whiteflies between seasons.'),
    ],
    monitorItems: ['Whitefly counts', 'New curled leaves', 'Plant vigor'],
    recheckAfterDays: '3-5 days',
  ),

  // ---------------- CHILLI ----------------
  DiseaseKnowledge(
    name: 'Chilli Leaf Spot',
    crop: CropType.chilli,
    symptoms:
        'Small brown circular spots with lighter centers on leaves; severe spots merge and leaves drop early.',
    favorable: FavorableConditions(
        humidityHigh: 80, tempMin: 20, tempMax: 30, needsLeafWetness: true),
    typicalSpreadHours: 48,
    doNow: [
      ('Remove spotted leaves',
          'Prune affected leaves with clean tools and dispose of them away from the field.'),
      ('Avoid overhead watering',
          'Splashing water spreads leaf spot spores plant to plant.'),
    ],
    prevent: [
      ('Improve air circulation',
          'Wider spacing helps leaves dry quickly after rain or watering.'),
      ('Mulch the beds',
          'Mulch reduces spore splash from the soil surface.'),
    ],
    monitorItems: ['New spots', 'Leaf drop', 'Humidity'],
    recheckAfterDays: '2-3 days',
  ),
  DiseaseKnowledge(
    name: 'Chilli Leaf Curl',
    crop: CropType.chilli,
    symptoms:
        'Young leaves curl and pucker, plants look stunted with shortened internodes.',
    favorable: FavorableConditions(
        humidityHigh: 60, tempMin: 25, tempMax: 35, needsLeafWetness: false),
    typicalSpreadHours: 72,
    doNow: [
      ('Inspect for whiteflies and thrips',
          'Leaf curl viruses are spread by sucking pests - check leaf undersides.'),
      ('Remove severely curled plants',
          'Destroy badly infected plants to protect healthy neighbors.'),
    ],
    prevent: [
      ('Manage sucking pests early',
          'Sticky traps and regular monitoring keep vectors low. Confirm treatments locally.'),
      ('Use healthy seedlings',
          'Start with certified, disease-free nursery stock when available.'),
    ],
    monitorItems: ['New curled leaves', 'Whitefly or thrips presence'],
    recheckAfterDays: '3-5 days',
  ),

  // ---------------- MAIZE ----------------
  DiseaseKnowledge(
    name: 'Maize Leaf Blight',
    crop: CropType.maize,
    symptoms:
        'Long, cigar-shaped grey-green to tan lesions running along the leaves, growing larger in humid weather.',
    favorable: FavorableConditions(
        humidityHigh: 80, tempMin: 18, tempMax: 27, needsLeafWetness: true),
    typicalSpreadHours: 48,
    doNow: [
      ('Check the lower canopy',
          'Northern corn leaf blight starts on lower leaves and moves upward.'),
      ('Note affected plant count',
          'Mark how many plants show lesions to track spread at the next check.'),
    ],
    prevent: [
      ('Rotate crops',
          'Maize-after-maize fields build up spores in the residue.'),
      ('Improve airflow',
          'Balanced plant density reduces humid, still air inside the canopy.'),
    ],
    monitorItems: ['Lesion size and count', 'Humidity', 'Rainfall'],
    recheckAfterDays: '3-5 days',
  ),
  DiseaseKnowledge(
    name: 'Maize Rust',
    crop: CropType.maize,
    symptoms:
        'Small, raised, cinnamon-brown pustules scattered on both leaf surfaces that rub off like powder.',
    favorable: FavorableConditions(
        humidityHigh: 85, tempMin: 16, tempMax: 28, needsLeafWetness: true),
    typicalSpreadHours: 48,
    doNow: [
      ('Scout several field spots',
          'Rust builds quickly - count pustules on a few plants across the field.'),
      ('Avoid heavy nitrogen stress',
          'Stressed plants show worse rust; keep nutrition balanced. Confirm locally.'),
    ],
    prevent: [
      ('Choose tolerant varieties next season',
          'Rust-tolerant hybrids are the most durable control.'),
      ('Manage field residue',
          'Infected residue carries rust to the next crop.'),
    ],
    monitorItems: ['Pustule density', 'Humidity', 'Leaf condition'],
    recheckAfterDays: '2-3 days',
  ),
];

/// Look up knowledge for a disease name (case-insensitive, trims).
DiseaseKnowledge? knowledgeFor(String diseaseName, {CropType? crop}) {
  final n = diseaseName.trim().toLowerCase();
  for (final d in kDiseaseKnowledge) {
    if (d.name.toLowerCase() == n) {
      if (crop == null || d.crop == crop) return d;
    }
  }
  // Fall back: same name on another crop is still the closest knowledge.
  for (final d in kDiseaseKnowledge) {
    if (d.name.toLowerCase() == n) return d;
  }
  return null;
}

/// Knowledge for a healthy result on a given crop.
DiseaseKnowledge healthyKnowledge(CropType crop) => _healthyFor(crop);

/// Best-match knowledge: prefer exact, then crop, then healthy.
DiseaseKnowledge knowledgeOrHealthy(String diseaseName, CropType crop) =>
    knowledgeFor(diseaseName, crop: crop) ??
    knowledgeFor(diseaseName) ??
    healthyKnowledge(crop);

/// Severity from the share of leaf area showing symptoms (visible assessment).
/// Category labels only - no fake numeric precision (Master Prompt section 10).
String severityFromArea(double affectedFraction) {
  if (affectedFraction <= 0.02) return 'NONE';
  if (affectedFraction <= 0.10) return 'LOW';
  if (affectedFraction <= 0.30) return 'MEDIUM';
  if (affectedFraction <= 0.55) return 'HIGH';
  return 'CRITICAL';
}

/// Re-check recommendation text key for a disease's interval.
String recheckLabel(DiseaseKnowledge k) =>
    'Check the crop again in ${k.recheckAfterDays}, or sooner if rain or humidity rises.';
