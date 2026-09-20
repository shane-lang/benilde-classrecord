using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using BenildeClassRecord.Api.Entities;
using Microsoft.IdentityModel.Tokens;

namespace BenildeClassRecord.Api.Services;

public class TokenService : ITokenService
{
    private readonly JwtSettings _settings;

    public TokenService(JwtSettings settings) => _settings = settings;

    public (string Token, DateTime ExpiresAt) CreateToken(Teacher teacher)
    {
        var expiresAt = DateTime.UtcNow.AddHours(_settings.ExpiryHours);

        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, teacher.Id.ToString()),
            new(JwtRegisteredClaimNames.Email, teacher.Email),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
            new(ClaimTypes.Name, teacher.FullName),
            new(ClaimTypes.NameIdentifier, teacher.Id.ToString())
        };

        claims.Add(new Claim(ClaimTypes.Role, teacher.IsAdmin ? "Admin" : "Teacher"));

        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_settings.Key));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var token = new JwtSecurityToken(
            issuer: _settings.Issuer,
            audience: _settings.Audience,
            claims: claims,
            expires: expiresAt,
            signingCredentials: credentials);

        return (new JwtSecurityTokenHandler().WriteToken(token), expiresAt);
    }
}

public class JwtSettings
{
    public const string SectionName = "Jwt";

    public string Key { get; set; } = string.Empty;

    public string Issuer { get; set; } = "BenildeClassRecord";
    public string Audience { get; set; } = "BenildeClassRecordApp";
    public int ExpiryHours { get; set; } = 12;
}