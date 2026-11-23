# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Synchronisation (doc/fin/sync.md): copies data from Moss into
# Hitobito, part by part. A run fetches, shows the plan, and writes only
# once confirmed.
module Wsjrdp::Sync
  # Every part, in the order a run handles them. The tree of the page comes
  # from their keys; a part's key never changes, the history relies on it.
  def self.parts = [MossApi::Departments, MossApi::Teams, MossApi::Users]

  def self.part(key) = parts.find { |part| part.key == key } || raise(KeyError, "unknown sync part #{key}")

  def self.part?(key) = parts.any? { |part| part.key == key }

  # An error as a part or run keeps it: "Class: message", at most 1000 characters.
  def self.error_text(error) = "#{error.class.name.demodulize}: #{error.message}".truncate(1000)

  # The parts of one source.
  def self.parts_of(source) = parts.select { |part| part.source == source.to_s }

  # The keys chosen plus everything they depend on, in the order of .parts.
  def self.expand(keys)
    wanted = Set.new
    add = lambda do |key|
      next if wanted.include?(key)

      wanted << key
      part(key).depends_on.each { |dependency| add.call(dependency) }
    end
    keys.each { |key| add.call(key) }
    parts.map(&:key).select { |key| wanted.include?(key) }
  end

  # One node of the tree: a group, or a part (leaf).
  Node = Data.define(:key, :children, :part) do
    def label = I18n.t("fin.sync.parts.#{key}._label")
  end

  # The tree of the given parts, built from their keys: a root without a
  # label, then e.g. Moss API > Organisationsstruktur > the parts.
  def self.tree(parts = self.parts)
    build = lambda do |prefix, members|
      members.group_by { |part| part.key.delete_prefix(prefix).split(".").first }.map do |segment, group|
        key = "#{prefix}#{segment}"
        leaf = group.find { |part| part.key == key }
        leaf ? Node.new(key: key, children: [], part: leaf) : Node.new(key: key, children: build.call("#{key}.", group), part: nil)
      end
    end
    Node.new(key: "", children: build.call("", parts), part: nil)
  end
end
