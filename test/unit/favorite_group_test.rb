require 'test_helper'

class FavoriteGroupTest < ActiveSupport::TestCase
  def setup
    @fav_group = create(:favorite_group)
  end

  context "searching by post id" do
    should "return the fav group" do
      posts = create_list(:post, 3)

      @fav_group.add(posts[0])
      assert_equal(@fav_group.id, FavoriteGroup.for_post(posts[0].id).first.id)

      @fav_group.add(posts[1])
      assert_equal(@fav_group.id, FavoriteGroup.for_post(posts[1].id).first.id)

      @fav_group.add(posts[2])
      assert_equal(@fav_group.id, FavoriteGroup.for_post(posts[2].id).first.id)
    end
  end

  context "expunging a post" do
    should "remove it from all favorite groups" do
      @post = create(:post_with_file, filename: "test.jpg")

      @fav_group.add(@post)
      assert_equal([@post.id], @fav_group.post_ids)

      @post.expunge!(create(:admin_user))
      assert_equal([], @fav_group.reload.post_ids)
    end
  end

  context "adding a post to a favgroup" do
    should "not allow adding duplicate posts" do
      post = create(:post)

      @fav_group.add(post)
      assert(@fav_group.valid?)
      assert_equal([post.id], @fav_group.reload.post_ids)

      @fav_group.add(post)
      assert_equal(false, @fav_group.valid?)
      assert_match(/Favgroup already contains post #{post.id}/, @fav_group.errors.full_messages.join)

      assert_equal([post.id], @fav_group.reload.post_ids)

      @fav_group.reload.update(post_ids: [post.id, post.id])
      refute(@fav_group.valid?)
      assert_equal([post.id], @fav_group.reload.post_ids)
    end

    should "not allow adding nonexistent posts" do
      @fav_group.update(post_ids: [0])

      refute(@fav_group.valid?)
      assert_equal([], @fav_group.reload.post_ids)
    end
  end

  context "when validating names" do
    subject { build(:favorite_group) }

    should_not allow_value("foo,bar").for(:name)
    should_not allow_value("foo*bar").for(:name)
    should_not allow_value("123").for(:name)
    should_not allow_value("_").for(:name)
    should_not allow_value("any").for(:name)
    should_not allow_value("none").for(:name)
  end
end
