import 'package:dio/dio.dart';

import 'llm_error.dart';

class LlmClientResponse {
  final int? statusCode;
  final dynamic data;

  const LlmClientResponse({required this.statusCode, required this.data});
}

class LlmClient {
  final Dio _dio;

  LlmClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 60),
              sendTimeout: const Duration(seconds: 20),
              contentType: 'application/json',
            ),
          );

  Future<LlmClientResponse> postCompletion({
    required String baseUrl,
    required String apiPath,
    required String apiKey,
    required Map<String, dynamic> requestBody,
  }) async {
    final normalizedBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = apiPath.startsWith('/') ? apiPath : '/$apiPath';

    try {
      final response = await _dio.post(
        '$normalizedBaseUrl$normalizedPath',
        options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
        data: requestBody,
      );

      return LlmClientResponse(
        statusCode: response.statusCode,
        data: response.data,
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        throw LlmException(
          type: LlmFailureType.unauthorized,
          message: 'LLM 鉴权失败（HTTP $status）',
          cause: e,
        );
      }
      throw LlmException(
        type: LlmFailureType.network,
        message: 'LLM 网络请求失败',
        cause: e,
      );
    } catch (e) {
      throw LlmException(
        type: LlmFailureType.unknown,
        message: 'LLM 请求发生未知错误',
        cause: e,
      );
    }
  }
}
