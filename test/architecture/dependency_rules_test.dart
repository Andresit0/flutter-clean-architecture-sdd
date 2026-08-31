import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

List<Directory> _featureDirs() =>
    Directory('lib/features').listSync().whereType<Directory>().toList();

List<File> _dartFilesIn(Directory dir) {
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where(
        (f) => !f.path.contains('.freezed.dart') && !f.path.contains('.g.dart'),
      )
      .toList();
}

List<String> _imports(File f) => f
    .readAsStringSync()
    .split('\n')
    .where((line) => line.startsWith('import'))
    .toList();

const _externalPackages = [
  'package:dio',
  'package:sembast',
  'package:flutter_secure_storage',
  'package:dart_jsonwebtoken',
  'package:bcrypt',
  'package:encrypt',
  'package:crypto',
  'package:fl_chart',
  'package:go_router',
  'package:internet_connection_checker_plus',
  'package:path_provider',
  'package:flutter_jailbreak_detection',
  'package:logger',
];

void main() {
  group('Architecture Dependency Rules', () {
    test(
      'Rule 1: domain/ does NOT import infrastructure, core, app, presentation, nor flutter',
      () {
        for (final feature in _featureDirs()) {
          for (final file in _dartFilesIn(
            Directory('${feature.path}/domain'),
          )) {
            for (final import in _imports(file)) {
              for (final forbidden in [
                'infrastructure/',
                'core/',
                'app/',
                'presentation/',
                'package:flutter/',
              ]) {
                expect(
                  import.contains(forbidden),
                  isFalse,
                  reason: '${file.path} imports $forbidden',
                );
              }
            }
          }
        }
      },
    );

    test(
      'Rule 2: shared/models/ does NOT import infrastructure, core, app, nor flutter',
      () {
        for (final file in _dartFilesIn(Directory('lib/shared/models'))) {
          for (final import in _imports(file)) {
            for (final forbidden in [
              'infrastructure/',
              'core/',
              'app/',
              'package:flutter/',
            ]) {
              expect(
                import.contains(forbidden),
                isFalse,
                reason: '${file.path} imports $forbidden',
              );
            }
          }
        }
      },
    );

    test('Rule 3: No .g.dart files in domain/ or shared/models/', () {
      for (final feature in _featureDirs()) {
        final domainG = Directory(
          '${feature.path}/domain',
        ).listSync().where((f) => f.path.endsWith('.g.dart'));
        expect(
          domainG,
          isEmpty,
          reason: '${feature.path}/domain contains .g.dart',
        );
      }

      final sharedG = Directory(
        'lib/shared/models',
      ).listSync(recursive: true).where((f) => f.path.endsWith('.g.dart'));
      expect(sharedG, isEmpty, reason: 'shared/models/ contains .g.dart');
    });

    test(
      'Rule 4: No Entity.fromJson() calls in lib/ (DTOs are the exception)',
      () {
        final dartFiles = Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (f) =>
                  f.path.endsWith('.dart') &&
                  !f.path.contains('.freezed.dart') &&
                  !f.path.contains('.g.dart'),
            );

        for (final file in dartFiles) {
          final content = file.readAsStringSync();
          if (content.contains('Entity.fromJson(')) {
            fail('${file.path} contains Entity.fromJson()');
          }
        }
      },
    );

    test('Rule 5: features/ does NOT import from other features/', () {
      final featureNames = _featureDirs().map((d) => d.path.split('/').last);

      for (final feature in featureNames) {
        for (final file in _dartFilesIn(Directory('lib/features/$feature'))) {
          for (final import in _imports(file)) {
            for (final otherFeature in featureNames) {
              if (otherFeature != feature &&
                  import.contains('features/$otherFeature')) {
                fail('${file.path} imports features/$otherFeature/');
              }
            }
          }
        }
      }
    });

    test(
      'Rule 6: features/ does NOT import external packages directly (only via wrappers)',
      () {
        for (final feature in _featureDirs()) {
          final featureFiles = _dartFilesIn(feature);

          for (final file in featureFiles) {
            for (final import in _imports(file)) {
              for (final pkg in _externalPackages) {
                expect(
                  import.contains(pkg),
                  isFalse,
                  reason:
                      '${file.path} imports $pkg directly. Must use wrapper.',
                );
              }
            }
          }
        }
      },
    );

    test('Rule 6b: feature tests (test/features, test/bdd, integration_test) '
        'does NOT import external packages directly (only via wrappers)', () {
      final testDirs = [
        Directory('test/features'),
        Directory('test/bdd'),
        Directory('integration_test'),
      ];

      for (final dir in testDirs) {
        for (final file in _dartFilesIn(dir)) {
          for (final import in _imports(file)) {
            for (final pkg in _externalPackages) {
              expect(
                import.contains(pkg),
                isFalse,
                reason:
                    '${file.path} imports $pkg directly. Must use wrapper.',
              );
            }
          }
        }
      }
    });

    test('Rule 7: domain/ does NOT import presentation/', () {
      for (final feature in _featureDirs()) {
        for (final file in _dartFilesIn(Directory('${feature.path}/domain'))) {
          for (final import in _imports(file)) {
            expect(
              import.contains('presentation/'),
              isFalse,
              reason: '${file.path} imports presentation/',
            );
          }
        }
      }
    });

    test('Rule 8: infrastructure/ does NOT import presentation/', () {
      for (final feature in _featureDirs()) {
        for (final file in _dartFilesIn(
          Directory('${feature.path}/infrastructure'),
        )) {
          for (final import in _imports(file)) {
            expect(
              import.contains('presentation/'),
              isFalse,
              reason: '${file.path} imports presentation/',
            );
          }
        }
      }
    });

    test(
      'Rule 9: domain/entities/ does NOT import external packages (only shared/ and freezed_annotation)',
      () {
        const allowedPrefixes = [
          'package:clean_architecture_sdd_harness/shared/',
          'package:freezed_annotation/',
        ];

        for (final feature in _featureDirs()) {
          final entityFiles = _dartFilesIn(
            Directory('${feature.path}/domain/entities'),
          );

          for (final file in entityFiles) {
            for (final import in _imports(file)) {
              final isAllowed = allowedPrefixes.any(
                (prefix) => import.contains(prefix),
              );
              final isDartSdk = import.contains('dart:');
              final isRelative = !import.contains('package:');
              if (!isAllowed && !isDartSdk && !isRelative) {
                fail('${file.path} imports "${import.trim()}" - not allowed');
              }
            }
          }
        }
      },
    );

    test('Rule 10: shared/ does NOT import l10n/ nor package:flutter/', () {
      for (final file in _dartFilesIn(Directory('lib/shared'))) {
        for (final import in _imports(file)) {
          expect(
            import.contains('/l10n/'),
            isFalse,
            reason:
                '${file.path} imports l10n/ — the shared layer must be '
                '100% pure Dart (no Flutter)',
          );
          expect(
            import.contains('package:flutter/'),
            isFalse,
            reason:
                '${file.path} imports flutter — the shared layer must be '
                '100% pure Dart (no Flutter)',
          );
        }
      }
    });

    test('Rule 11: features/ does NOT import app/', () {
      for (final feature in _featureDirs()) {
        for (final file in _dartFilesIn(feature)) {
          for (final import in _imports(file)) {
            expect(
              import.contains('/app/'),
              isFalse,
              reason:
                  '${file.path} imports app/ — unidirectional DI violated. '
                  'Import providers from core/ directly.',
            );
          }
        }
      }
    });

    test(
      'Rule 12: domain/ does NOT import external packages (only shared/, freezed_annotation and relatives)',
      () {
        for (final feature in _featureDirs()) {
          final featureName = feature.path.split('/').last;
          for (final file in _dartFilesIn(
            Directory('${feature.path}/domain'),
          )) {
            final content = file.readAsStringSync();
            expect(
              content.contains('.g.dart'),
              isFalse,
              reason:
                  '${file.path} — domain/ does not allow .g.dart (without '
                  'domain serialization; use DTOs in infrastructure/)',
            );

            for (final import in _imports(file)) {
              final isShared = import.contains(
                'package:clean_architecture_sdd_harness/shared/',
              );
              final isFreezed = import.contains('package:freezed_annotation/');
              final isOwnDomain = import.contains(
                'features/$featureName/domain/',
              );
              final isDartSdk = import.contains('dart:');
              final isRelative = !import.contains('package:');
              if (!isShared &&
                  !isFreezed &&
                  !isOwnDomain &&
                  !isDartSdk &&
                  !isRelative) {
                fail(
                  '${file.path} imports "${import.trim()}" - not allowed '
                  'in domain/ (only dart:, shared/, freezed_annotation and its '
                  'own domain)',
                );
              }
            }
          }
        }
      },
    );

    test(
      'Rule 13: no implementation_imports (package:.../src/) fuera de allowlist',
      () {
        const allowlist = <String>[];
        final root = Directory.current.path;

        final dartFiles = Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (f) =>
                  f.path.endsWith('.dart') &&
                  !f.path.contains('.g.dart') &&
                  !f.path.contains('.freezed.dart'),
            );

        for (final file in dartFiles) {
          for (final import in _imports(file)) {
            if (import.contains('package:') && import.contains('/src/')) {
              final relative = file.path.replaceFirst('$root/', '');
              expect(
                allowlist.contains(relative),
                isTrue,
                reason:
                    '${file.path} imports package:.../src/ — must be isolated '
                    'in an allowlist file (e.g. sembast_codec.dart)',
              );
            }
          }
        }
      },
    );

    test('Rule 14: core/ does NOT import features/ nor app/', () {
      for (final file in _dartFilesIn(Directory('lib/core'))) {
        for (final import in _imports(file)) {
          expect(
            import.contains('/features/'),
            isFalse,
            reason:
                '${file.path} imports features/ — core/ must be '
                'feature-agnostic',
          );
          expect(
            import.contains('/app/'),
            isFalse,
            reason:
                '${file.path} imports app/ — core/ does not know the '
                'composition root',
          );
        }
      }
    });

    test(
      'Rule 15: presentation/ does NOT import infrastructure/, core/, nor app/',
      () {
        for (final feature in _featureDirs()) {
          for (final file in _dartFilesIn(
            Directory('${feature.path}/presentation'),
          )) {
            for (final import in _imports(file)) {
              for (final forbidden in ['infrastructure/', '/core/', '/app/']) {
                expect(
                  import.contains(forbidden),
                  isFalse,
                  reason:
                      '${file.path} imports $forbidden — presentation '
                      'only depends on di/, domain/, shared/, design_system/ and l10n/',
                );
              }
            }
          }
        }
      },
    );

    test(
      'Rule 16: No static access to AppEnvironment outside core/config/',
      () {
        final dartFiles = Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (f) =>
                  f.path.endsWith('.dart') &&
                  !f.path.contains('.freezed.dart') &&
                  !f.path.contains('.g.dart'),
            );

        for (final file in dartFiles) {
          if (file.path.contains('lib/core/config/')) continue;
          expect(
            file.readAsStringSync().contains(RegExp(r'AppEnvironment\.\w')),
            isFalse,
            reason:
                '${file.path} uses a static member of AppEnvironment — the '
                'configuration is read via environmentProvider or the '
                'instancia concreta (const DevEnvironment()...)',
          );
        }
      },
    );

    test(
      'Rule 17a: every public method of domain/repositories/* returns Future<Result<...>>',
      () {
        for (final feature in _featureDirs()) {
          final repoDir = Directory('${feature.path}/domain/repositories');
          if (!repoDir.existsSync()) continue;
          for (final file in _dartFilesIn(repoDir)) {
            final content = file.readAsStringSync();
            final methodRegex = RegExp(r'Future<[^>]*>\s+(\w+)\s*\(');
            for (final match in methodRegex.allMatches(content)) {
              final returnType = match.group(0)!.split(RegExp(r'\s+')).first;
              expect(
                returnType.startsWith('Future<Result<'),
                isTrue,
                reason:
                    '${file.path} — ${match.group(1)} must return '
                    'Future<Result<...>> (canonical Result policy). '
                    'Encontrado: $returnType',
              );
            }
          }
        }
      },
    );

    test(
      'Rule 17b: every usecase implements IUseCase<In, Out> (uniform contract)',
      () {
        for (final feature in _featureDirs()) {
          final usecaseDir = Directory('${feature.path}/domain/usecases');
          if (!usecaseDir.existsSync()) continue;
          for (final file in _dartFilesIn(usecaseDir)) {
            final content = file.readAsStringSync();
            final classRegex = RegExp(r'class\s+\w+UseCase\b');
            for (final match in classRegex.allMatches(content)) {
              final declEnd = content.indexOf('{', match.start);
              final declaration = content.substring(match.start, declEnd);
              expect(
                declaration.contains('implements IUseCase<'),
                isTrue,
                reason:
                    '${file.path} — ${match.group(0)} must implement '
                    'IUseCase<In, Out>',
              );
            }
          }
        }
      },
    );

    test('Rule 18: usecases depend on other usecases via IUseCase<In, Out>, '
        'never on concrete classes (DIP)', () {
      for (final feature in _featureDirs()) {
        final usecaseDir = Directory('${feature.path}/domain/usecases');
        if (!usecaseDir.existsSync()) continue;
        for (final file in _dartFilesIn(usecaseDir)) {
          for (final line in file.readAsStringSync().split('\n')) {
            final trimmed = line.trimLeft();
            if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
            final fieldRegex = RegExp(r'final\s+(\w*UseCase)\b');
            for (final match in fieldRegex.allMatches(line)) {
              final type = match.group(1)!;
              expect(
                type == 'IUseCase',
                isTrue,
                reason:
                    '${file.path} — field typed as "$type"; usecases '
                    'must depend on IUseCase<In, Out>, never on '
                    'a concrete class (DIP, Rule 18). Line: ${line.trim()}',
              );
            }
          }
        }
      }
    });

    test('Rule 19a: every interface in domain/repositories and domain/datasources '
        'has exactly 1 concrete implementation in infrastructure/ '
        '(1 contrato = 1 impl)', () {
      for (final feature in _featureDirs()) {
        final featureName = feature.path.split('/').last;
        final infraDir = Directory('${feature.path}/infrastructure');
        if (!infraDir.existsSync()) continue;
        final infraFiles = _dartFilesIn(infraDir);

        for (final contractsDir in ['repositories', 'datasources']) {
          final contractsPath = '${feature.path}/domain/$contractsDir';
          final contractsDirObj = Directory(contractsPath);
          if (!contractsDirObj.existsSync()) continue;

          for (final file in _dartFilesIn(contractsDirObj)) {
            final interfaceRegex = RegExp(
              r'(?:abstract\s+)?(?:interface\s+)?class\s+(I\w+)',
            );
            for (final match in interfaceRegex.allMatches(
              file.readAsStringSync(),
            )) {
              final iface = match.group(1)!;
              final implRegex = RegExp(
                'class\\s+(\\w+)(?:\\s+extends\\s+[A-Za-z0-9_<>, ]+)?'
                '\\s+implements\\s+[^{]*\\b$iface\\b',
              );
              final impls = <String>{};
              for (final infraFile in infraFiles) {
                for (final implMatch in implRegex.allMatches(
                  infraFile.readAsStringSync(),
                )) {
                  impls.add(implMatch.group(1)!);
                }
              }
              expect(
                impls.length,
                1,
                reason:
                    '$iface ($contractsDir of feature $featureName) must '
                    'have exactly 1 concrete implementation in '
                    'infrastructure/ (Rule 19a). Encontradas: $impls',
              );
            }
          }
        }
      }
    });

    test('Rule 19b: no concrete class in infrastructure/ implements >1 '
        'contrato de dominio (1 clase = 1 contrato)', () {
      for (final feature in _featureDirs()) {
        final infraDir = Directory('${feature.path}/infrastructure');
        if (!infraDir.existsSync()) continue;
        for (final file in _dartFilesIn(infraDir)) {
          final content = file.readAsStringSync();
          final classRegex = RegExp(
            r'class\s+(\w+)(?:\s+extends\s+\w+)?\s+implements\s+([^{]+)\{',
          );
          for (final match in classRegex.allMatches(content)) {
            final impls = match
                .group(2)!
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            expect(
              impls.length,
              1,
              reason:
                  '${file.path} — ${match.group(1)} implementa '
                  '${impls.join(", ")}: requires 1 class = 1 contract '
                  '(Rule 19b)',
            );
          }
        }
      }
    });

    test('Rule 20: core/database/tables/ separates DI from implementation — only '
        'the *_providers.dart files declare Riverpod providers', () {
      final tablesDir = Directory('lib/core/database/tables');
      if (!tablesDir.existsSync()) return;
      for (final file in _dartFilesIn(tablesDir)) {
        if (file.path.endsWith('_providers.dart')) continue;
        final content = file.readAsStringSync();
        expect(
          content.contains('Provider<'),
          isFalse,
          reason:
              '${file.path} declares a provider — providers live in '
              '*_providers.dart files (DI separate from the '
              'implementation, Rule 20)',
        );
        expect(
          content.contains('package:flutter_riverpod/'),
          isFalse,
          reason:
              '${file.path} imports riverpod — providers live in '
              '*_providers.dart files (Rule 20)',
        );
      }
    });

    test('Rule 21: go_router is confined to lib/app/ (composition root) — '
        'features use IAppNavigator, never the package', () {
      final dartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) =>
                f.path.endsWith('.dart') &&
                !f.path.contains('.g.dart') &&
                !f.path.contains('.freezed.dart'),
          );

      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        if (content.contains('package:go_router/')) {
          expect(
            file.path.contains('lib/app/'),
            isTrue,
            reason:
                '${file.path} imports go_router — go_router is '
                'confinado a lib/app/ (composition root). Features navegan '
                'via IAppNavigator (appNavigatorProvider).',
          );
        }
      }
    });

    test(
      'Rule 22: shared/error is only imported via the barrel _error.lib.dart',
      () {
        final dartFiles = Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (f) =>
                  f.path.endsWith('.dart') &&
                  !f.path.contains('.g.dart') &&
                  !f.path.contains('.freezed.dart'),
            );

        for (final file in dartFiles) {
          for (final import in _imports(file)) {
            final isRawErrorImport =
                import.contains('shared/error/') &&
                !import.contains('_error.lib.dart');
            expect(
              isRawErrorImport,
              isFalse,
              reason:
                  '${file.path} imports shared/error directly — '
                  'always use the barrel _error.lib.dart (LEARN.md barrel rule)',
            );
          }
        }
      },
    );

    test('Rule 23: shared/exceptions is only imported via the barrel '
        '_exceptions.lib.dart', () {
      final dartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) =>
                f.path.endsWith('.dart') &&
                !f.path.contains('.g.dart') &&
                !f.path.contains('.freezed.dart'),
          );

      for (final file in dartFiles) {
        for (final import in _imports(file)) {
          final isRawExceptionsImport =
              import.contains('shared/exceptions/') &&
              !import.contains('_exceptions.lib.dart');
          expect(
            isRawExceptionsImport,
            isFalse,
            reason:
                '${file.path} imports shared/exceptions directly — '
                'always use the barrel _exceptions.lib.dart',
          );
        }
      }
    });

    test('Rule 24: shared/functions/ is imported directly — without barrel '
        '_functions.lib.dart', () {
      final dartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) =>
                f.path.endsWith('.dart') &&
                !f.path.contains('.g.dart') &&
                !f.path.contains('.freezed.dart'),
          );

      for (final file in dartFiles) {
        for (final import in _imports(file)) {
          expect(
            import.contains('shared/functions/_functions.lib.dart'),
            isFalse,
            reason:
                '${file.path} imports a barrel of shared/functions — '
                'import online_first.dart directly (same as '
                'shared/router/)',
          );
        }
      }
    });

    test('Rule 25: shared/functions/online_first.dart imports ONLY shared/ '
        '(Shared Kernel puro)', () {
      final file = File('lib/shared/functions/online_first.dart');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'online_first.dart must exist as an online-first helper',
      );

      for (final import in _imports(file)) {
        for (final forbidden in [
          'core/',
          'app/',
          'features/',
          'l10n/',
          'design_system/',
          'package:flutter/',
        ]) {
          expect(
            import.contains(forbidden),
            isFalse,
            reason:
                '${file.path} imports $forbidden — shared/ cannot '
                'depend on concrete layers nor Flutter',
          );
        }
        if (import.contains('package:clean_architecture_sdd_harness/')) {
          expect(
            import.contains('package:clean_architecture_sdd_harness/shared/'),
            isTrue,
            reason: '${file.path} can only import from shared/',
          );
        }
      }
    });

    test('Rule 26: shared/interfaces is only imported via the barrel '
        '_interfaces.lib.dart (no re-exports outside the folder)', () {
      final dartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) =>
                f.path.endsWith('.dart') &&
                !f.path.contains('.g.dart') &&
                !f.path.contains('.freezed.dart'),
          );

      for (final file in dartFiles) {
        for (final import in _imports(file)) {
          final isRawInterfaceImport =
              import.contains('shared/interfaces/') &&
              !import.contains('_interfaces.lib.dart');
          expect(
            isRawInterfaceImport,
            isFalse,
            reason:
                '${file.path} imports shared/interfaces directly — '
                'always use the barrel _interfaces.lib.dart',
          );
        }

        if (!file.path.contains('lib/shared/interfaces/')) {
          for (final line in file.readAsStringSync().split('\n')) {
            final trimmed = line.trimLeft();
            if (trimmed.startsWith('export') &&
                trimmed.contains('shared/interfaces/')) {
              fail(
                '${file.path} re-exports shared/interfaces — the barrels '
                'external barrels must not re-export Shared Kernel interfaces',
              );
            }
          }
        }
      }
    });

    test(
      'Barrel convention: _*.lib.dart are pure-export (no library; nor part)',
      () {
        final barrels = Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.lib.dart'))
            .toList();

        expect(
          barrels,
          isNotEmpty,
          reason: 'at least one barrel _*.lib.dart is expected',
        );

        for (final barrel in barrels) {
          final content = barrel.readAsStringSync();
          expect(
            content.contains('library;'),
            isFalse,
            reason:
                '${barrel.path} must not declare library; — barrels '
                'are pure-export (repo convention, MD/APP_BARREL_PATTERN.md)',
          );
          expect(
            RegExp(r'^part ', multiLine: true).hasMatch(content),
            isFalse,
            reason:
                '${barrel.path} must not use part — barrels '
                'centralized with export (repo convention)',
          );
          expect(
            content.trimLeft().startsWith('export'),
            isTrue,
            reason: '${barrel.path} must start with export',
          );
        }
      },
    );

    test('Rule 27: app/ does NOT re-export symbols from features/ (the composition '
        'root imports features explicitly, without hidden re-exports)', () {
      for (final file in _dartFilesIn(Directory('lib/app'))) {
        for (final line in file.readAsStringSync().split('\n')) {
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('export') && trimmed.contains('features/')) {
            fail(
              '${file.path} re-exports features/ — the composition root '
              'must import feature symbols explicitly; hidden '
              're-exports crean dependencias ocultas/transitivas. '
              'Line: $trimmed',
            );
          }
        }
      }
    });

    test('Rule 28: constructor-injected dependencies (I*, VoidCallback, '
        'Function()) must be private fields (_field)', () {
      for (final file in _dartFilesIn(Directory('lib'))) {
        for (final line in file.readAsStringSync().split('\n')) {
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
          final fieldRegex = RegExp(
            r'final\s+(I[A-Z][A-Za-z0-9]*(?:<[^;]*>)?|VoidCallback|Future<String\?> Function\(\))\s+[a-z]\w*\s*;',
          );
          final match = fieldRegex.firstMatch(line);
          expect(
            match,
            isNull,
            reason:
                '${file.path} — publicly injected dependency: '
                '${line.trim()}. The constructor-injected fields must '
                'be private fields (_field); the public named parameter '
                'derives from the initializing formal (this._x → x).',
          );
        }
      }
    });

    test('Rule 29: no *.freezed.dart / *.g.dart is orphaned — its sibling '
        'part-of source must exist and declare it as part', () {
      final orphans = <String>[];
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>()) {
        final path = file.path;
        if (!path.endsWith('.freezed.dart') && !path.endsWith('.g.dart')) {
          continue;
        }
        final partOf = file
            .readAsStringSync()
            .split('\n')
            .map((l) => l.trim())
            .firstWhere((l) => l.startsWith('part of '), orElse: () => '');
        if (partOf.isEmpty) {
          orphans.add('$path — no declara "part of"');
          continue;
        }
        final target = partOf
            .replaceFirst('part of ', '')
            .replaceAll("'", '')
            .replaceAll(';', '')
            .trim();
        final source = File('${file.parent.path}/$target');
        if (!source.existsSync()) {
          orphans.add('$path → missing part-of source: $target');
          continue;
        }
        final generatedName = path.split('/').last;
        if (!source.readAsStringSync().contains("part '$generatedName'")) {
          orphans.add('$path → ${source.path} does not declare it as part');
        }
      }
      expect(
        orphans,
        isEmpty,
        reason: 'Orphaned generated files:\n${orphans.join('\n')}',
      );
    });
  });
}
