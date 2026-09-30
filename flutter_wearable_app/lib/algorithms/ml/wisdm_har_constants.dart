// Auto-generated Smartwatch HAR Model Constants for CIRIS Wearable
// Dataset: WISDM Smartwatch Motion (Accelerometer + Gyroscope)

class WisdmHarConstants {
  static const String modelId = 'model_wisdm_har_random_forest';
  static const double accuracy = 1.0;
  static const double f1Score = 1.0;

  static const List<String> featureNames = [
    'accel_x_mean',
    'accel_y_mean',
    'accel_z_mean',
    'accel_mag_mean',
    'accel_x_std',
    'accel_y_std',
    'accel_z_std',
    'accel_mag_std',
    'accel_jerk_mean',
    'gyro_x_mean',
    'gyro_y_mean',
    'gyro_z_mean',
    'gyro_mag_mean',
    'gyro_mag_std',
    'motion_energy',
    'spectral_entropy',
  ];

  static const List<double> scalerMeans = [
    11.816040476190476,
    11.794566666666665,
    11.78339761904762,
    20.485566666666667,
    1.0014571428571428,
    0.9881761904761907,
    1.0031666666666665,
    0.9818976190476189,
    1.1302047619047617,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    428.6340119047619,
    1.6426952380952382,
  ];

  static const List<double> scalerStds = [
    1.638036370905511,
    1.648374205762218,
    1.6291057123886061,
    2.8295594487706004,
    0.07041336501537981,
    0.07072548139688316,
    0.07122004020627991,
    0.07064180432393122,
    0.11859039138861636,
    1.0,
    1.0,
    1.0,
    1.0,
    1.0,
    116.20821419691998,
    0.16694499942935434,
  ];

  static const Map<int, String> activityMap = {
    0: 'Walking',
    1: 'Jogging',
    2: 'Stairs',
    3: 'Sitting',
    4: 'Standing',
    5: 'Typing',
    6: 'Brushing Teeth',
    7: 'Eating Soup',
    8: 'Eating Chips',
    9: 'Eating Pasta',
    10: 'Drinking',
    11: 'Eating Sandwich',
    12: 'Kicking',
    13: 'Catching',
    14: 'Dribbling',
    15: 'Writing',
    16: 'Clapping',
    17: 'Folding Clothes',
  };
}
