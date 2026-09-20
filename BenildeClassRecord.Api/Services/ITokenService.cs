using BenildeClassRecord.Api.Entities;

namespace BenildeClassRecord.Api.Services;

public interface ITokenService
{
    (string Token, DateTime ExpiresAt) CreateToken(Teacher teacher);
}