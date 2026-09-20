using BenildeClassRecord.Api.Data;
using BenildeClassRecord.Api.Dtos;
using BenildeClassRecord.Api.Entities;
using BenildeClassRecord.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace BenildeClassRecord.Api.Controllers;

[ApiController]

[Authorize(Roles = "Teacher")]
[Route("api/classes/{classId:int}/categories")]
public class GradingCategoriesController : ControllerBase
{
    private readonly AppDbContext _db;

    public GradingCategoriesController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<List<GradingCategoryDto>>> GetAll(int classId)
    {
        if (await this.OwnedClassAsync(_db, classId) is null)
            return NotFound(new ApiError("That class wasn't found."));

        var categories = await _db.GradingCategories
            .AsNoTracking()
            .Where(c => c.ClassId == classId)
            .ToListAsync();

        var counts = await _db.Assessments
            .Where(a => categories.Select(c => c.Id).Contains(a.CategoryId))
            .GroupBy(a => a.CategoryId)
            .Select(g => new { CategoryId = g.Key, Count = g.Count() })
            .ToDictionaryAsync(x => x.CategoryId, x => x.Count);

        return Ok(CategoryMapper.ToTree(categories, counts));
    }

    [HttpPost]
    public async Task<ActionResult<GradingCategoryDto>> Create(
        int classId, [FromBody] SaveCategoryRequest request)
    {
        if (await this.OwnedClassAsync(_db, classId) is null)
            return NotFound(new ApiError("That class wasn't found."));

        if (request.ParentId is int parentId)
        {
            var parent = await _db.GradingCategories
                .FirstOrDefaultAsync(c => c.Id == parentId && c.ClassId == classId);

            if (parent is null)
                return BadRequest(new ApiError("That parent category isn't in this class."));

            if (parent.ParentId is not null)
                return BadRequest(new ApiError(
                    "A subcategory can't hold subcategories of its own. The breakdown is two levels deep."));

            if (parent.IsAttendance)
                return BadRequest(new ApiError("Attendance is computed automatically and can't be split."));
        }

        var category = new GradingCategory
        {
            ClassId = classId,
            ParentId = request.ParentId,
            Name = request.Name.Trim(),
            Weight = request.Weight,
            SortOrder = request.SortOrder
        };

        _db.GradingCategories.Add(category);
        await _db.SaveChangesAsync();

        return Ok(new GradingCategoryDto
        {
            Id = category.Id,
            ParentId = category.ParentId,
            Name = category.Name,
            Weight = category.Weight,
            IsAttendance = category.IsAttendance,
            SortOrder = category.SortOrder
        });
    }

    [HttpPut("{categoryId:int}")]
    public async Task<IActionResult> Update(
        int classId, int categoryId, [FromBody] SaveCategoryRequest request)
    {
        var category = await this.OwnedCategoryAsync(_db, categoryId);
        if (category is null || category.ClassId != classId)
            return NotFound(new ApiError("That category wasn't found."));

        if (!category.IsAttendance) category.Name = request.Name.Trim();
        category.Weight = request.Weight;
        category.SortOrder = request.SortOrder;

        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpDelete("{categoryId:int}")]
    public async Task<IActionResult> Delete(int classId, int categoryId)
    {
        var category = await this.OwnedCategoryAsync(_db, categoryId);
        if (category is null || category.ClassId != classId)
            return NotFound(new ApiError("That category wasn't found."));

        if (category.IsAttendance)
            return BadRequest(new ApiError("Attendance is built in and can't be deleted."));

        var childCount = await _db.GradingCategories.CountAsync(c => c.ParentId == categoryId);
        if (childCount > 0)
            return Conflict(new ApiError(
                $"This category still holds {childCount} subcategor{(childCount == 1 ? "y" : "ies")}. Delete those first."));

        var itemCount = await _db.Assessments.CountAsync(a => a.CategoryId == categoryId);
        if (itemCount > 0)
            return Conflict(new ApiError(
                $"This category still holds {itemCount} recorded item{(itemCount == 1 ? "" : "s")}. Delete those first."));

        _db.GradingCategories.Remove(category);
        await _db.SaveChangesAsync();
        return NoContent();
    }
}