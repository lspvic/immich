import { Injectable } from '@nestjs/common';
import { Insertable, Kysely, Updateable, sql } from 'kysely';
import { InjectKysely } from 'nestjs-kysely';
import { DummyValue, GenerateSql } from 'src/decorators';
import { AlbumUserRole } from 'src/enum';
import { DB } from 'src/schema';
import { AlbumUserTable } from 'src/schema/tables/album-user.table';

export type AlbumPermissionId = {
  albumId: string;
  userId: string;
};

@Injectable()
export class AlbumUserRepository {
  constructor(@InjectKysely() private db: Kysely<DB>) {}

  @GenerateSql({ params: [{ userId: DummyValue.UUID, albumId: DummyValue.UUID }] })
  create(albumUser: Insertable<AlbumUserTable>) {
    return this.db
      .insertInto('album_user')
      .values(albumUser)
      .returning(['userId', 'albumId', 'role'])
      .executeTakeFirstOrThrow();
  }

  @GenerateSql(
    { params: [{ userId: DummyValue.UUID, albumId: DummyValue.UUID }, { role: AlbumUserRole.Viewer }] },
    { params: [{ userId: DummyValue.UUID, albumId: DummyValue.UUID }, { showInTimeline: true }], name: 'withShowInTimeline' },
  )
  async update({ userId, albumId }: AlbumPermissionId, dto: Updateable<AlbumUserTable>) {
    await this.db
      .updateTable('album_user')
      .set(dto)
      .where('userId', '=', userId)
      .where('albumId', '=', albumId)
      .execute();

    // When showInTimeline changes, force re-sync of all album assets by bumping their updateId.
    // Without this, mobile clients that already synced the album assets would keep stale ownerId values
    // because the sync engine only re-sends assets whose album_asset.updateId has changed.
    if (dto.showInTimeline !== undefined) {
      await this.db
        .updateTable('album_asset')
        .set({ updateId: sql`immich_uuid_v7()` })
        .where('albumId', '=', albumId)
        .execute();
    }
  }

  @GenerateSql({ params: [DummyValue.UUID] })
  async getTimelineAlbumIds(userId: string): Promise<string[]> {
    const rows = await this.db
      .selectFrom('album_user')
      .select('albumId')
      .where('userId', '=', userId)
      .where('showInTimeline', '=', true)
      .execute();
    return rows.map((r) => r.albumId);
  }

  @GenerateSql({ params: [{ userId: DummyValue.UUID, albumId: DummyValue.UUID }] })
  async delete({ userId, albumId }: AlbumPermissionId): Promise<void> {
    await this.db.deleteFrom('album_user').where('userId', '=', userId).where('albumId', '=', albumId).execute();
  }
}
