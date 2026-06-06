using Microsoft.EntityFrameworkCore;
using mywebapp.Models;

namespace mywebapp.Data;

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<Note> Notes { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<Note>(entity =>
        {
            entity.ToTable("notes");

            entity.HasKey(note => note.Id)
                .HasName("pk_notes");

            entity.Property(note => note.Id)
                .HasColumnName("id")
                .ValueGeneratedOnAdd();

            entity.Property(note => note.Title)
                .HasColumnName("title")
                .IsRequired()
                .HasMaxLength(255);

            entity.Property(note => note.Content)
                .HasColumnName("content")
                .IsRequired();

            entity.Property(note => note.CreatedAt)
                .HasColumnName("created_at")
                .IsRequired();

            entity.HasIndex(note => note.CreatedAt)
                .HasDatabaseName("ix_notes_created_at");

            entity.HasIndex(note => note.Title)
                .HasDatabaseName("ix_notes_title");
        });
    }
}
