use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .create_table(
                Table::create()
                    .table(Playlist::Table)
                    .if_not_exists()
                    .col(
                        ColumnDef::new(Playlist::Id)
                            .big_integer()
                            .not_null()
                            .auto_increment()
                            .primary_key(),
                    )
                    .col(ColumnDef::new(Playlist::Name).text().not_null())
                    .col(
                        ColumnDef::new(Playlist::Mode)
                            .text()
                            .not_null()
                            .default("sequential"),
                    )
                    .col(
                        ColumnDef::new(Playlist::IntervalSecs)
                            .big_integer()
                            .not_null()
                            .default(0i64),
                    )
                    .col(
                        ColumnDef::new(Playlist::CreatedAt)
                            .big_integer()
                            .not_null()
                            .default(0i64),
                    )
                    .col(
                        ColumnDef::new(Playlist::UpdatedAt)
                            .big_integer()
                            .not_null()
                            .default(0i64),
                    )
                    .to_owned(),
            )
            .await?;

        manager
            .create_table(
                Table::create()
                    .table(PlaylistItem::Table)
                    .if_not_exists()
                    .col(
                        ColumnDef::new(PlaylistItem::Id)
                            .big_integer()
                            .not_null()
                            .auto_increment()
                            .primary_key(),
                    )
                    .col(
                        ColumnDef::new(PlaylistItem::PlaylistId)
                            .big_integer()
                            .not_null(),
                    )
                    .col(
                        ColumnDef::new(PlaylistItem::EntryId)
                            .big_integer()
                            .not_null(),
                    )
                    .col(
                        ColumnDef::new(PlaylistItem::Position)
                            .big_integer()
                            .not_null()
                            .default(0i64)
                            .check(Expr::col(PlaylistItem::Position).gte(0)),
                    )
                    .foreign_key(
                        ForeignKey::create()
                            .name("fk_playlist_item_playlist")
                            .from(PlaylistItem::Table, PlaylistItem::PlaylistId)
                            .to(Playlist::Table, Playlist::Id)
                            .on_delete(ForeignKeyAction::Cascade),
                    )
                    .foreign_key(
                        ForeignKey::create()
                            .name("fk_playlist_item_item")
                            .from(PlaylistItem::Table, PlaylistItem::EntryId)
                            .to(Item::Table, Item::Id)
                            .on_delete(ForeignKeyAction::Cascade),
                    )
                    .to_owned(),
            )
            .await?;

        manager
            .create_index(
                Index::create()
                    .name("idx_playlist_item_playlist_pos")
                    .table(PlaylistItem::Table)
                    .col(PlaylistItem::PlaylistId)
                    .col(PlaylistItem::Position)
                    .unique()
                    .to_owned(),
            )
            .await?;
        manager
            .create_index(
                Index::create()
                    .name("idx_playlist_item_playlist_entry")
                    .table(PlaylistItem::Table)
                    .col(PlaylistItem::PlaylistId)
                    .col(PlaylistItem::EntryId)
                    .unique()
                    .to_owned(),
            )
            .await?;
        manager
            .create_index(
                Index::create()
                    .name("idx_playlist_item_entry")
                    .table(PlaylistItem::Table)
                    .col(PlaylistItem::EntryId)
                    .to_owned(),
            )
            .await?;

        Ok(())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .drop_table(Table::drop().table(PlaylistItem::Table).to_owned())
            .await?;
        manager
            .drop_table(Table::drop().table(Playlist::Table).to_owned())
            .await?;
        Ok(())
    }
}

#[derive(DeriveIden)]
enum Playlist {
    Table,
    Id,
    Name,
    Mode,
    IntervalSecs,
    CreatedAt,
    UpdatedAt,
}

#[derive(DeriveIden)]
enum PlaylistItem {
    Table,
    Id,
    PlaylistId,
    EntryId,
    Position,
}

#[derive(DeriveIden)]
enum Item {
    Table,
    Id,
}
