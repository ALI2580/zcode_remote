import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/entitlement.dart';

const codingProvider = 'builtin:bigmodel-coding-plan';
EntitlementSource selected(String suffix, {String provider = codingProvider}) =>
    EntitlementSource.resolve(provider, {
      'modelProviderFamilyModes': {'bigmodel': 'oauth', 'zai': 'oauth'},
      'modelProviderFamilySelectedKeys': {
        provider.startsWith('builtin:zai') ? 'zai' : 'bigmodel':
            'team-plan:$provider:$suffix'
      }
    })!;

EntitlementSnapshot teamSnapshot(
        {String product = 'product',
        String org = 'org',
        String project = 'real-project',
        String provider = codingProvider}) =>
    EntitlementSnapshot.parse({
      'provider': {'id': provider},
      'context': {
        'scope': 'team',
        'organizationId': org,
        'projectId': project,
        'productId': product
      }
    })!;

void main() {
  test(
      'legacy project zero matches its product without requesting project zero',
      () {
    expect(selected('product:0').accepts(teamSnapshot()), isTrue);
    expect(
        selected('product:0').accepts(teamSnapshot(product: 'other')), isFalse);
  });

  test('the official incomplete organization form remains a legacy project key',
      () {
    final source = selected('product::unused-third-part');
    expect(source.organizationId, isNull);
    expect(source.projectId, isNull);
  });

  test('subscribed team projects resolve encoded and project-only selections',
      () {
    final products = {
      'productList': [
        {
          'productId': 'ignored',
          'subscribed': false,
          'organizationId': 'wrong',
          'projectId': 'project:two'
        },
        {
          'productId': 'renewed-product',
          'subscribed': true,
          'family': 'bigmodel',
          'teamProjects': [
            {'organizationId': 'org:one', 'projectId': 'project:two'}
          ]
        }
      ]
    };
    final resolved =
        selected('old-product:project%3Atwo').resolveTeamProducts(products)!;
    expect(resolved.organizationId, 'org:one');
    expect(resolved.projectId, 'project:two');
    expect(resolved.key,
        'team-plan:$codingProvider:renewed-product:org%3Aone:project%3Atwo');
    expect(
        selected('renewed-product:other-org:project%3Atwo')
            .resolveTeamProducts(products),
        isNull);
    expect(
        selected('renewed-product:0', provider: 'builtin:zai-coding-plan')
            .resolveTeamProducts(products),
        isNull);
  });

  test(
      'legacy snapshot binding requires a matching team with complete identities',
      () {
    final source = selected('product:0');
    final fromDetails = EntitlementSnapshot.parse({
      'provider': {'id': codingProvider},
      'context': {
        'scope': 'team',
        'organizationId': 'org',
        'projectId': 'project'
      },
      'subscription': {
        'details': [
          {'productId': 'product'}
        ]
      }
    })!;
    expect(source.resolveTeamSnapshot(fromDetails)!.projectId, 'project');
    expect(
        source.resolveTeamSnapshot(EntitlementSnapshot.parse({
          'provider': {'id': codingProvider},
          'context': {'scope': 'personal'}
        })),
        isNull);
    expect(source.resolveTeamSnapshot(teamSnapshot(product: 'other')), isNull);
    expect(
        source.resolveTeamSnapshot(
            teamSnapshot(provider: 'builtin:zai-coding-plan')),
        isNull);
  });
}
