import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  const workflowPath = '.github/workflows/ci.yml';

  late Map workflow;
  setUpAll(() {
    final raw = File(workflowPath).readAsStringSync();
    workflow = Map<dynamic, dynamic>.from(loadYaml(raw));
  });

  group('Workflow anti-masking gates', () {
    test('Analyze and Test run on Linux (ubuntu-latest)', () {
      expect(
        workflow['jobs']['analyze']['runs-on'],
        'ubuntu-latest',
        reason: 'Analyze must run on Linux to keep macOS usage minimal',
      );
      expect(
        workflow['jobs']['test']['runs-on'],
        'ubuntu-latest',
        reason: 'Test must run on Linux to keep macOS usage minimal',
      );
    });

    test('Test Goldens runs on Linux (ubuntu-latest)', () {
      expect(
        workflow['jobs']['test-goldens']['runs-on'],
        'ubuntu-latest',
        reason: 'Test Goldens must run on Linux (cross-platform goldens)',
      );
    });

    test('Golden tests are tagged with golden', () {
      final files = Directory('test')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('_golden_test.dart'))
          .toList();

      expect(files, isNotEmpty, reason: 'expected at least one golden test');

      for (final file in files) {
        final content = file.readAsStringSync();
        expect(
          content.contains("@Tags(['golden'])"),
          isTrue,
          reason:
              '${file.path} must declare @Tags([\'golden\']) so it runs '
              'only in the tagged Test Goldens job, never masked in Test',
        );
      }
    });

    test('Build jobs do NOT depend on Test (no masking)', () {
      for (final jobName in ['build-ios', 'build-android', 'test-goldens']) {
        final needs = workflow['jobs'][jobName]['needs'] as List?;
        expect(
          needs?.contains('test'),
          isFalse,
          reason:
              '$jobName must not need test — '
              'a build that depends on tests passing masks failures',
        );
        expect(
          needs?.contains('analyze'),
          isTrue,
          reason: '$jobName should depend on analyze',
        );
      }
    });

    test('macOS usage is minimal (<= 2 jobs)', () {
      final macJobs = workflow['jobs'].entries.where((entry) {
        final job = entry.value as Map;
        return job['runs-on'] == 'macos-latest';
      }).toList();

      expect(
        macJobs.length,
        lessThanOrEqualTo(2),
        reason:
            'Only essential jobs may run on macOS (Build iOS). '
            'Currently: ${macJobs.map((e) => e.key).toList()}',
      );
    });

    test('A secret-scanning job exists (gitleaks)', () {
      final job = workflow['jobs']['gitleaks'] as Map?;
      expect(
        job,
        isNotNull,
        reason:
            'a gitleaks job must exist — removing the secret scan '
            'gate would silently disable leak detection',
      );
      expect(
        job?['runs-on'],
        'ubuntu-latest',
        reason: 'gitleaks must run on Linux (free runner)',
      );
    });

    test('Test and Test Goldens jobs keep the tag flags', () {
      final runs = <String>[];
      for (final jobName in ['test', 'test-goldens']) {
        final steps = workflow['jobs'][jobName]['steps'] as List;
        for (final step in steps) {
          final run = (step as Map)['run'] as String?;
          if (run != null && run.contains('flutter test')) {
            runs.add('$jobName: $run');
          }
        }
      }

      expect(
        runs.any(
          (r) => r.startsWith('test:') && r.contains('--exclude-tags golden'),
        ),
        isTrue,
        reason:
            'Test must keep --exclude-tags golden so the coverage run '
            'never silently executes golden tests',
      );
      expect(
        runs.any(
          (r) => r.startsWith('test-goldens:') && r.contains('--tags golden'),
        ),
        isTrue,
        reason: 'Test Goldens must keep --tags golden so goldens actually run',
      );
    });
  });

  group('Toolchain pin gates', () {
    test('pubspec.yaml declares an exact Flutter SDK pin', () {
      final raw = File('pubspec.yaml').readAsStringSync();
      final pubspec = Map<dynamic, dynamic>.from(loadYaml(raw));
      final environment = pubspec['environment'];
      expect(
        environment,
        isA<Map>(),
        reason: 'pubspec.yaml must declare an environment section',
      );
      final flutter = (environment as Map)['flutter'];
      expect(
        flutter,
        isA<String>(),
        reason:
            'pubspec.yaml environment.flutter is the single source of truth '
            'for the Flutter SDK version',
      );
      expect(
        (flutter as String).trim(),
        matches(RegExp(r'^\d+\.\d+\.\d+$')),
        reason:
            'environment.flutter must be an exact version so '
            'flutter-version-file can resolve it',
      );
    });

    test('CI reads the Flutter pin from pubspec.yaml, never hardcodes it', () {
      const workflowPaths = <String>[
        '.github/workflows/ci.yml',
        '.github/workflows/deploy-web.yml',
      ];
      var actionSteps = 0;
      for (final path in workflowPaths) {
        final raw = File(path).readAsStringSync();
        final workflow = Map<dynamic, dynamic>.from(loadYaml(raw));
        final jobs = workflow['jobs'] as Map;
        for (final job in jobs.entries) {
          final steps = (job.value as Map)['steps'] as List;
          for (final step in steps) {
            final uses = (step as Map)['uses'] as String?;
            if (uses == null || !uses.contains('subosito/flutter-action')) {
              continue;
            }
            actionSteps++;
            final withBlock = step['with'] as Map?;
            expect(
              withBlock,
              isNotNull,
              reason:
                  '$path job ${job.key} sets up Flutter without a with block',
            );
            expect(
              withBlock!.containsKey('flutter-version'),
              isFalse,
              reason:
                  '$path job ${job.key} must not hardcode flutter-version; '
                  'use flutter-version-file',
            );
            expect(
              withBlock['flutter-version-file'],
              'pubspec.yaml',
              reason:
                  '$path job ${job.key} must read the SDK pin from '
                  'pubspec.yaml',
            );
          }
        }
      }
      expect(
        actionSteps,
        greaterThan(0),
        reason: 'expected at least one subosito/flutter-action step',
      );
    });

    test(
      'codegen toolchain resolves to analyzer 13 and freezed 4 or newer',
      () {
        final lock = Map<dynamic, dynamic>.from(
          loadYaml(File('pubspec.lock').readAsStringSync()),
        );
        final packages = lock['packages'] as Map;
        final freezedVersion =
            (packages['freezed'] as Map)['version'] as String;
        final analyzerVersion =
            (packages['analyzer'] as Map)['version'] as String;
        expect(
          int.parse(freezedVersion.split('.').first),
          greaterThanOrEqualTo(4),
          reason:
              'freezed must resolve to 4.x or newer so its generated code no '
              'longer emits the final parameters Dart 3.13 rejects (issue #62)',
        );
        expect(
          int.parse(analyzerVersion.split('.').first),
          greaterThanOrEqualTo(13),
          reason:
              'analyzer must resolve to 13.x or newer (freezed 4 toolchain)',
        );
      },
    );

    test('pubspec.yaml Dart SDK lower bound is at least 3.13.0', () {
      final raw = File('pubspec.yaml').readAsStringSync();
      final pubspec = Map<dynamic, dynamic>.from(loadYaml(raw));
      final environment = pubspec['environment'] as Map;
      final sdk = environment['sdk'] as String;
      final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(sdk);
      expect(
        match,
        isNotNull,
        reason: 'environment.sdk must contain a semantic version',
      );
      final major = int.parse(match!.group(1)!);
      final minor = int.parse(match.group(2)!);
      expect(
        major > 3 || (major == 3 && minor >= 13),
        isTrue,
        reason:
            'environment.sdk lower bound must be at least 3.13.0 so the '
            'analyzer 13 toolchain matches the Dart runtime',
      );
    });
  });

  group('Test config gates (dart_test.yaml)', () {
    const configPath = 'dart_test.yaml';

    late Map config;
    setUpAll(() {
      final raw = File(configPath).readAsStringSync();
      config = Map<dynamic, dynamic>.from(loadYaml(raw));
    });

    test('dart_test.yaml exists and declares the golden tag', () {
      expect(
        File(configPath).existsSync(),
        isTrue,
        reason:
            'dart_test.yaml must exist so the golden tag is declared and '
            'no "A tag was used that wasn\'t specified in dart_test.yaml" '
            'warning is emitted on every run',
      );
      final tags = config['tags'];
      expect(
        tags,
        isA<Map>(),
        reason: 'dart_test.yaml must declare a tags: section',
      );
      expect(
        (tags as Map).containsKey('golden'),
        isTrue,
        reason: 'the golden tag must be declared in dart_test.yaml',
      );
    });

    test('dart_test.yaml does not exclude golden tests', () {
      final excludeTags = config['exclude_tags'];
      if (excludeTags is Iterable) {
        expect(
          excludeTags.contains('golden'),
          isFalse,
          reason:
              'exclude_tags takes precedence over --tags golden '
              '(test docs: "the exclusions take precedence") — '
              'exclude_tags: golden would run 0 golden tests in the '
              'Test Goldens CI job and pass green (masking)',
        );
      }
    });

    test('dart_test.yaml does not set include_tags', () {
      expect(
        config.containsKey('include_tags'),
        isFalse,
        reason:
            'a top-level include_tags is intersected with the CLI '
            '(--tags/--exclude-tags) and would change the default run, '
            'masking unit/widget tests in the Test CI job',
      );
    });

    test('all tags used in test/ are declared in dart_test.yaml', () {
      final tags = config['tags'] as Map;
      final declared = tags.keys.map((key) => key.toString()).toSet();

      final used = <String>{};
      final tagRegex = RegExp(r"@Tags\(\s*\[([^\]]*)\]");
      for (final file in Directory(
        'test',
      ).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final content = file.readAsStringSync();
        for (final match in tagRegex.allMatches(content)) {
          final names = match.group(1)?.split(',') ?? const [];
          for (final name in names) {
            final tag = name
                .trim()
                .replaceAll("'", '')
                .replaceAll('"', '')
                .replaceAll('\\', '');
            if (tag.isNotEmpty) used.add(tag);
          }
        }
      }

      final undeclared = used.difference(declared);
      expect(
        undeclared,
        isEmpty,
        reason:
            'every tag used in test/ must be declared in dart_test.yaml '
            'or the "A tag was used..." warning returns. '
            'Undeclared tags: $undeclared',
      );
    });
  });
}
